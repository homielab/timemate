//  Created by homielab.com

import AppKit
import Combine
import SwiftUI
import UserNotifications
import os

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate,
  UNUserNotificationCenterDelegate, ObservableObject
{

  // MARK: - Properties
  private var statusItem: NSStatusItem!
  private var popover: NSPopover!
  private let timer = PomodoroTimer.shared
  private lazy var popoverModel = PopoverTimerModel(timer: timer)
  private var hostingController: NSHostingController<AnyView>!
  private var menuBarHostingView: PassThroughHostingView!
  private let sleepPreventer = SleepPreventer()
  private var breakOverlayController: BreakOverlayWindowController!
  private var escapeKeyMonitor: Any?
  private var keepAwakeEnabled = false
  /// What shows the countdown right now; decides the timer's `TickMode`.
  private var isPopoverOpen = false
  private var isVoiceOverRunning = false
  /// Global shortcuts; registered only when running as the app, not under tests.
  private(set) lazy var hotKeyManager = HotKeyManager { [weak self] action in
    self?.timer.perform(action)
  }
  private var cancellables = Set<AnyCancellable>()
  /// Keeps the menu bar item's VoiceOver label current; only while VoiceOver is on.
  private var accessibilityLabelUpdates: AnyCancellable?
  private var voiceOverObservation: NSKeyValueObservation?
  /// Asks the popover to show its settings ("Settings…" in the right-click menu).
  let openSettingsRequests = PassthroughSubject<Void, Never>()
  @AppStorage(SettingsKey.hideMenuBarTime) private var hideMenuBarTime = false

  fileprivate static var isRunningTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }

  /// The saved session history, or an in-memory one when hosting tests so they
  /// never touch the user's statistics.
  fileprivate static func makeSessionHistory() -> SessionHistory {
    SessionHistory(fileURL: isRunningTests ? nil : SessionHistory.defaultFileURL())
  }

  // MARK: - App Lifecycle
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Running as the test host: skip the app shell so tests drive the state
    // machine without status items, popovers or notification prompts.
    if Self.isRunningTests {
      return
    }

    // Register defaults
    UserDefaults.standard.register(defaults: [
      SettingsKey.overlayEnabled: true,
      SettingsKey.overlaySkipFullscreen: true,
      SettingsKey.notificationsEnabled: true,
      SettingsKey.breakThroughFocus: true,
      SettingsKey.keepAwake: false,
      SettingsKey.hideDockIcon: true,
      SettingsKey.alwaysVisible: false,
      SettingsKey.hotKeyStartPauseEnabled: true,
      SettingsKey.hotKeySkipEnabled: true,
      SettingsKey.showProgressCircle: true,
      SettingsKey.autoStartNextSession: true,
      SettingsKey.autoStartOnLaunch: false,
      SettingsKey.showTimerAtLogin: false,
      SettingsKey.keepBreakScreenOpen: true,
      SettingsKey.dailyGoal: DailyGoal.off,
      SettingsKey.statisticsDays: SessionStatistics.weekLength,
    ])

    // Defaults must be registered before the first read of any setting.
    self.setDockIcon(hidden: UserDefaults.standard.hideDockIcon)
    observeTimerForKeepAwake()
    self.setKeepAwake(enabled: UserDefaults.standard.keepAwake)

    let notificationCenter = UNUserNotificationCenter.current()
    notificationCenter.delegate = self
    notificationCenter.setNotificationCategories([SessionNotification.category()])
    notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) {
      _, error in
      if let error {
        Logger.app.error("Notification authorization failed: \(error.localizedDescription)")
      }
    }

    NSColorPanel.shared.showsAlpha = true

    statusItem = NSStatusBar.system.statusItem(
      withLength: MenuBarView.width(hideTime: hideMenuBarTime))
    menuBarHostingView = PassThroughHostingView(rootView: AnyView(EmptyView()))
    statusItem.button?.subviews.forEach { $0.removeFromSuperview() }
    statusItem.button?.addSubview(menuBarHostingView)
    layoutMenuBar(hideTime: hideMenuBarTime)

    statusItem.button?.target = self
    statusItem.button?.action = #selector(statusItemClicked)
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    observeVoiceOverForAccessibilityLabel()

    // --- Popover Setup ---
    let contentView = ContentView().environmentObject(popoverModel).environmentObject(self)
      .environmentObject(hotKeyManager)
    hostingController = NSHostingController(rootView: AnyView(contentView))
    popover = NSPopover()
    popover.delegate = self
    popover.behavior = Self.popoverBehavior(
      alwaysVisible: UserDefaults.standard.bool(forKey: SettingsKey.alwaysVisible))
    popover.contentViewController = hostingController
    hotKeyManager.activate()

    // --- Initial State ---
    updatePopoverSize()
    let defaults = UserDefaults.standard
    let showsPopover = LaunchBehavior.showsPopover(
      isFirstLaunch: !defaults.bool(forKey: SettingsKey.hasLaunchedBefore),
      isLoginLaunch: LaunchBehavior.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent),
      showTimerAtLogin: defaults.bool(forKey: SettingsKey.showTimerAtLogin))
    defaults.set(true, forKey: SettingsKey.hasLaunchedBefore)
    if showsPopover {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        if !self.popover.isShown {
          self.togglePopover()
        }
      }
    }

    // --- Auto-start Timer ---
    // A session restored from the last run (running or paused) is left as is.
    if UserDefaults.standard.bool(forKey: SettingsKey.autoStartOnLaunch), timer.state == .idle {
      timer.startTimer()
    }

    // --- Break Overlay ---
    breakOverlayController = BreakOverlayWindowController(timer: timer)
    observeTimerForTickMode()
  }

  /// Ticks every second only while something shows the countdown.
  private func updateTickMode() {
    let overlayShown =
      timer.state == .active && timer.isBreak && !timer.isBreakPostponed
      && UserDefaults.standard.bool(forKey: SettingsKey.overlayEnabled)
    timer.tickMode = TickMode.mode(
      popoverOpen: isPopoverOpen, menuBarShowsTime: !hideMenuBarTime,
      breakOverlayShown: overlayShown, voiceOverRunning: isVoiceOverRunning)
  }

  /// The break screen comes and goes with the session.
  private func observeTimerForTickMode() {
    // @Published emits before the change lands; read the timer on the next pass.
    Publishers.CombineLatest3(timer.$state, timer.$currentSessionType, timer.$isBreakPostponed)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.updateTickMode() }
      .store(in: &cancellables)
  }

  func updatePopoverSize() {
    DispatchQueue.main.async {
      self.popover.contentSize = self.hostingController.view.fittingSize
    }
  }

  func setDockIcon(hidden: Bool) {
    NSApp.setActivationPolicy(hidden ? .accessory : .regular)
  }

  func setKeepAwake(enabled: Bool) {
    keepAwakeEnabled = enabled
    updateSleepPrevention(state: timer.state, sessionType: timer.currentSessionType)
  }

  /// Holds the assertion only while a focus session is running; released on pause, idle, breaks.
  private func observeTimerForKeepAwake() {
    // @Published emits before the change lands, so use the emitted values.
    Publishers.CombineLatest(timer.$state, timer.$currentSessionType)
      .sink { [weak self] state, sessionType in
        self?.updateSleepPrevention(state: state, sessionType: sessionType)
      }
      .store(in: &cancellables)
  }

  private func updateSleepPrevention(state: PomodoroState, sessionType: SessionType) {
    if SleepPreventer.shouldHoldAssertion(
      keepAwake: keepAwakeEnabled, state: state, sessionType: sessionType)
    {
      sleepPreventer.enable()
    } else {
      sleepPreventer.disable()
    }
  }

  /// "Keep window on top" keeps the popover open when the user clicks elsewhere;
  /// it then closes only via the menu bar icon or the Escape key.
  static func popoverBehavior(alwaysVisible: Bool) -> NSPopover.Behavior {
    alwaysVisible ? .applicationDefined : .transient
  }

  func setPopoverBehavior(alwaysVisible: Bool) {
    popover.behavior = Self.popoverBehavior(alwaysVisible: alwaysVisible)
  }

  /// Closes the popover on Escape whatever its behavior, since an
  /// application-defined popover is not dismissed by the system.
  private func installEscapeKeyMonitor() {
    guard escapeKeyMonitor == nil else { return }
    escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      // While a shortcut is being recorded, Escape cancels the recording.
      guard let self, event.keyCode == DoubleEscDetector.escKeyCode, self.popover.isShown,
        !self.hotKeyManager.isRecording,
        event.window === self.popover.contentViewController?.view.window
      else { return event }
      self.popover.performClose(nil)
      return nil
    }
  }

  private func removeEscapeKeyMonitor() {
    if let monitor = escapeKeyMonitor { NSEvent.removeMonitor(monitor) }
    escapeKeyMonitor = nil
  }

  /// Sizes the status item and updates the menu bar view in place.
  private func layoutMenuBar(hideTime: Bool) {
    let width = MenuBarView.width(hideTime: hideTime)
    statusItem.length = width
    menuBarHostingView.rootView = AnyView(MenuBarView(timer: timer, hideTime: hideTime))
    menuBarHostingView.frame = NSRect(
      x: 0, y: 0, width: width, height: NSStatusBar.system.thickness)
  }

  func updateMenuBarWidth(hideTime: Bool) {
    let wasShown = popover.isShown

    // Close popover if shown to reposition it
    if wasShown {
      popover.performClose(nil)
    }

    layoutMenuBar(hideTime: hideTime)
    // @AppStorage may not hold the new value yet.
    hideMenuBarTime = hideTime
    updateTickMode()

    // Reopen popover if it was shown
    if wasShown {
      DispatchQueue.main.async {
        self.togglePopover()
      }
    }
  }

  /// Left click toggles the popover; right click (or Control-click) opens the menu.
  @objc private func statusItemClicked() {
    let event = NSApp.currentEvent
    if StatusItemMenu.opensMenu(
      eventType: event?.type, modifierFlags: event?.modifierFlags ?? [])
    {
      showStatusItemMenu()
    } else {
      togglePopover()
    }
  }

  private func showStatusItemMenu() {
    guard let button = statusItem.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    }
    // Attaching the menu only for this click keeps left clicks on the popover
    // and lets the system place and highlight the menu like any menu extra.
    statusItem.menu = makeStatusItemMenu()
    button.performClick(nil)
    statusItem.menu = nil
  }

  /// Built on every right click, so titles follow the timer's current state.
  private func makeStatusItemMenu() -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.addItem(
      menuItem(
        StatusItemMenu.startPauseTitle(
          state: timer.state, isWaitingToContinue: timer.isWaitingToContinue),
        action: #selector(menuStartPause)))
    menu.addItem(menuItem(NSLocalizedString("Skip", comment: ""), action: #selector(menuSkip)))
    let reset = menuItem(NSLocalizedString("Reset", comment: ""), action: #selector(menuReset))
    reset.isEnabled = StatusItemMenu.isResetEnabled(state: timer.state)
    menu.addItem(reset)
    menu.addItem(.separator())
    menu.addItem(
      menuItem(NSLocalizedString("Settings…", comment: ""), action: #selector(menuOpenSettings)))
    menu.addItem(.separator())
    menu.addItem(
      menuItem(
        NSLocalizedString("Quit", comment: ""), action: #selector(NSApplication.terminate(_:)),
        target: NSApp, keyEquivalent: "q"))
    return menu
  }

  private func menuItem(
    _ title: String, action: Selector, target: AnyObject? = nil, keyEquivalent: String = ""
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.target = target ?? self
    return item
  }

  @objc private func menuStartPause() { timer.perform(.startPause) }
  @objc private func menuSkip() { timer.perform(.skip) }
  @objc private func menuReset() { timer.stopTimer() }

  @objc private func menuOpenSettings() {
    if !popover.isShown {
      togglePopover()
    }
    DispatchQueue.main.async { self.openSettingsRequests.send() }
  }

  // MARK: - VoiceOver label

  /// VoiceOver reads the menu bar item as "TimeMate, Focus, 12 minutes,
  /// 34 seconds remaining". The label follows the timer only while VoiceOver
  /// is on, so the menu bar does no extra work every second otherwise.
  private func observeVoiceOverForAccessibilityLabel() {
    voiceOverObservation = NSWorkspace.shared.observe(
      \.isVoiceOverEnabled, options: [.initial, .new]
    ) { [weak self] workspace, _ in
      let enabled = workspace.isVoiceOverEnabled
      DispatchQueue.main.async { self?.setAccessibilityLabelUpdates(enabled: enabled) }
    }
  }

  private func setAccessibilityLabelUpdates(enabled: Bool) {
    isVoiceOverRunning = enabled
    updateTickMode()
    guard enabled else {
      accessibilityLabelUpdates = nil
      statusItem.button?.setAccessibilityLabel(Bundle.main.appName)
      return
    }
    updateStatusItemAccessibilityLabel()
    // objectWillChange fires before the new values land; read them on the next pass.
    accessibilityLabelUpdates = timer.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.updateStatusItemAccessibilityLabel() }
  }

  private func updateStatusItemAccessibilityLabel() {
    let label = StatusItemMenu.accessibilityLabel(
      sessionType: timer.currentSessionType, state: timer.state,
      secondsRemaining: timer.timeRemaining, isBreakPostponed: timer.isBreakPostponed,
      isWaitingToContinue: timer.isWaitingToContinue)
    if statusItem.button?.accessibilityLabel() != label {
      statusItem.button?.setAccessibilityLabel(label)
    }
  }

  @objc func togglePopover() {
    guard let button = statusItem.button else { return }

    if popover.isShown {
      popover.performClose(nil)
    } else {
      NSApp.activate(ignoringOtherApps: true)
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
  }

  // MARK: - UNUserNotificationCenterDelegate

  /// Show the banner even while TimeMate is in front (e.g. the break screen
  /// just appeared); without this macOS hides it silently.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let response = NotificationResponse(actionIdentifier: response.actionIdentifier)
    DispatchQueue.main.async { [weak self] in
      switch response {
      case .timerAction(let action):
        self?.timer.handleNotificationAction(action)
      case .openPopover:
        if let self, !self.popover.isShown {
          self.togglePopover()
        }
      case .ignore:
        break
      }
      completionHandler()
    }
  }

  // MARK: - NSPopoverDelegate
  // The countdown is only fed to the popover while it is open, so a closed
  // popover doesn't re-render every second.
  func popoverWillShow(_ notification: Notification) {
    // Brings the countdown up to date before the popover reads it.
    isPopoverOpen = true
    installEscapeKeyMonitor()
    updateTickMode()
    popoverModel.setPopoverVisible(true)
  }

  func popoverDidClose(_ notification: Notification) {
    isPopoverOpen = false
    removeEscapeKeyMonitor()
    updateTickMode()
    popoverModel.setPopoverVisible(false)
  }

  // MARK: - Reopen Window from Dock
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !popover.isShown {
      togglePopover()
    }
    return true
  }
}

// MARK: - Pass-through hosting view for menu bar (allows clicks to reach NSStatusBarButton)
// NOTE: Using AnyView instead of a generic parameter to work around a Swift 6.2 compiler crash
// in the SIL optimizer (EarlyPerfInliner) when processing the deinit of generic NSHostingView subclasses.
private class PassThroughHostingView: NSHostingView<AnyView> {
  override func hitTest(_ point: NSPoint) -> NSView? {
    // Return nil so that clicks pass through to the underlying NSStatusBarButton
    return nil
  }
}

private struct MenuBarView: View {
  @ObservedObject var timer: PomodoroTimer
  let hideTime: Bool

  static func width(hideTime: Bool) -> CGFloat { hideTime ? 24 : 90 }

  private var iconName: String {
    switch timer.state {
    case .paused:
      return "pause.circle.fill"
    case .idle:
      return "timer"
    case .active:
      return timer.currentSessionType == .focus
        ? "play.circle.fill" : timer.currentSessionType.style.iconName
    }
  }

  private var accentColor: Color {
    if timer.state == .paused {
      return .orange
    }
    let activeColor = timer.currentSessionType.style.color

    if timer.currentSessionType == .shortBreak || timer.currentSessionType == .longBreak {
      return activeColor.opacity(0.8)
    }
    return activeColor
  }

  private var foregroundColor: Color {
    if timer.state == .active {
      return .white
    }
    return Color(nsColor: .headerTextColor)
  }

  var body: some View {
    // The status item button carries the VoiceOver label (time included), so
    // its drawing stays out of the accessibility tree.
    HStack(spacing: 4) {
      Image(systemName: iconName)
        .font(.system(size: NSFont.systemFontSize + 2))
        .padding(.horizontal, 4)
        .background(
          RoundedRectangle(cornerRadius: 4)
            .fill(timer.state == .active ? accentColor : .clear)
        )
        .foregroundColor(timer.state == .active ? .white : Color(nsColor: .headerTextColor))

      if !hideTime {
        Text(timer.timeRemaining.toMinuteSecondString())
          .font(.system(size: NSFont.systemFontSize + 1, design: .monospaced).weight(.bold))
          .foregroundColor(foregroundColor)
      }
    }
    .frame(
      width: Self.width(hideTime: hideTime), height: NSStatusBar.system.thickness,
      alignment: .center
    )
    .accessibilityHidden(true)
  }
}

extension PomodoroTimer {
  /// The app's one timer, shared by the menu bar, the popover and the
  /// Shortcuts actions (which may run before the app shell is set up).
  static let shared = PomodoroTimer(history: AppDelegate.makeSessionHistory())
}
