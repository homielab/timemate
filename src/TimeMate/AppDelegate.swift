//  Created by homielab.com

import AppKit
import Combine
import SwiftUI
import UserNotifications
import os

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate,
  UNUserNotificationCenterDelegate, ObservableObject
{
  private var statusItemController: StatusItemController!
  private var popover: NSPopover!
  /// The popover's window, for key handlers that must ignore other windows.
  var popoverWindow: NSWindow? { popover?.contentViewController?.view.window }
  private let timer = PomodoroTimer.shared
  private lazy var popoverModel = PopoverTimerModel(timer: timer)
  private var hostingController: NSHostingController<AnyView>!
  private let sleepPreventer = SleepPreventer()
  private var breakOverlayController: BreakOverlayWindowController!
  private var escapeKeyMonitor: Any?
  private var keepAwakeEnabled = false
  private var isPopoverOpen = false
  private var isDisplayAsleep = false
  private var isScreenLocked = false
  private(set) lazy var hotKeyManager = HotKeyManager { [weak self] action in
    guard let self, let message = self.timer.perform(action) else { return }
    self.showHotKeyMessage(message)
  }
  private var cancellables = Set<AnyCancellable>()
  private var defaultsObserver: DefaultsObserver?
  let openSettingsRequests = PassthroughSubject<Void, Never>()
  private var menuBarStyle = MenuBarTimeStyle.minutesSeconds

  /// Explains why a global shortcut did nothing (see `HotKeyMessage`).
  private func showHotKeyMessage(_ message: String) {
    HotKeyMessage.live().show(message)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

    SettingsKey.registerDefaults()
    MenuBarTimeStyle.migrate()
    menuBarStyle = MenuBarTimeStyle.current()
    setDockIcon(hidden: UserDefaults.standard.hideDockIcon)
    observeTimerForKeepAwake()
    setKeepAwake(enabled: UserDefaults.standard.keepAwake)
    SessionNotification.configure(delegate: self)
    NSColorPanel.shared.showsAlpha = true

    statusItemController = StatusItemController(
      timer: timer,
      menuBarStyle: menuBarStyle,
      onTogglePopover: { [weak self] in self?.togglePopover() },
      onOpenSettings: { [weak self] in self?.openSettings() },
      onTickModeNeedsUpdate: { [weak self] in self?.updateTickMode() },
      isPopoverShown: { [weak self] in self?.popover.isShown ?? false },
      onClosePopover: { [weak self] in self?.popover.performClose(nil) }
    )

    setupPopover()
    checkInitialLaunchBehavior()

    if LaunchBehavior.shouldAutoStartOnLaunch(
      enabled: UserDefaults.standard.bool(forKey: SettingsKey.autoStartOnLaunch),
      state: timer.state, sessionType: timer.currentSessionType,
      isWaiting: timer.isWaitingToContinue)
    {
      timer.startTimer()
    }

    breakOverlayController = BreakOverlayWindowController(timer: timer)
    observeTimerForTickMode()
  }

  private func setupPopover() {
    let contentView = ContentView().environmentObject(popoverModel).environmentObject(self)
      .environmentObject(hotKeyManager)
    hostingController = NSHostingController(rootView: AnyView(contentView))
    popover = NSPopover()
    popover.delegate = self
    popover.behavior = Self.popoverBehavior(
      alwaysVisible: UserDefaults.standard.bool(forKey: SettingsKey.alwaysVisible))
    popover.contentViewController = hostingController
    hotKeyManager.activate()
    // A shortcut held by another app (or by the copy that is quitting during a
    // restart) is tried again whenever TimeMate comes to the front.
    NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      .sink { [weak self] _ in self?.hotKeyManager.retryFailed() }
      .store(in: &cancellables)
    updatePopoverSize()
  }

  private func checkInitialLaunchBehavior() {
    let defaults = UserDefaults.standard
    let shows = LaunchBehavior.showsPopover(
      isFirstLaunch: !defaults.bool(forKey: SettingsKey.hasLaunchedBefore),
      isLoginLaunch: LaunchBehavior.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent),
      showTimerAtLogin: defaults.bool(forKey: SettingsKey.showTimerAtLogin))
    defaults.set(true, forKey: SettingsKey.hasLaunchedBefore)
    if shows {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        if !self.popover.isShown { self.togglePopover() }
      }
    }
  }

  /// Ticks every second only while something shows the countdown.
  func updateTickMode() {
    let overlayShown = BreakOverlayRules.shouldShowOverlay(
      state: timer.state,
      sessionType: timer.currentSessionType,
      isWaiting: timer.isWaitingToContinue,
      isPostponed: timer.isBreakPostponed,
      enabled: UserDefaults.standard.bool(forKey: SettingsKey.overlayEnabled)
    )
    timer.tickMode = TickMode.mode(
      popoverOpen: isPopoverOpen,
      menuBarStyle: menuBarStyle,
      breakOverlayShown: overlayShown,
      voiceOverRunning: statusItemController?.isVoiceOverRunning ?? false,
      screenAsleep: isDisplayAsleep || isScreenLocked
    )
  }

  private func observeTimerForTickMode() {
    Publishers.CombineLatest4(
      timer.$state, timer.$currentSessionType, timer.$isBreakPostponed, timer.$isWaitingToContinue
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in self?.updateTickMode() }
    .store(in: &cancellables)

    observeScreenState()

    // updateTickMode reads only the break screen switch from the defaults.
    defaultsObserver = DefaultsObserver(
      defaults: .standard, keys: [SettingsKey.overlayEnabled]
    ) { [weak self] in self?.updateTickMode() }
  }

  /// With the display off or the screen locked nothing shows the countdown, so
  /// ticking drops to `.atEnd`; on wake or unlock it catches up right away.
  private func observeScreenState() {
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    let distributedCenter = DistributedNotificationCenter.default()
    let lockedName = Notification.Name(PomodoroTimer.screenLockedNotificationName)
    let unlockedName = Notification.Name("com.apple.screenIsUnlocked")
    workspaceCenter.publisher(for: NSWorkspace.screensDidSleepNotification)
      .sink { [weak self] _ in self?.setScreenState(displayAsleep: true) }
      .store(in: &cancellables)
    workspaceCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
      .sink { [weak self] _ in self?.setScreenState(displayAsleep: false) }
      .store(in: &cancellables)
    distributedCenter.publisher(for: lockedName)
      .sink { [weak self] _ in self?.setScreenState(locked: true) }
      .store(in: &cancellables)
    distributedCenter.publisher(for: unlockedName)
      .sink { [weak self] _ in self?.setScreenState(locked: false) }
      .store(in: &cancellables)
  }

  private func setScreenState(displayAsleep: Bool? = nil, locked: Bool? = nil) {
    if let displayAsleep { isDisplayAsleep = displayAsleep }
    if let locked { isScreenLocked = locked }
    updateTickMode()
    // Show the right time the moment the screen is back.
    if !(isDisplayAsleep || isScreenLocked) { timer.handleTick() }
  }

  func updatePopoverSize() {
    DispatchQueue.main.async { self.popover.contentSize = self.hostingController.view.fittingSize }
  }

  func setDockIcon(hidden: Bool) { NSApp.setActivationPolicy(hidden ? .accessory : .regular) }

  func setKeepAwake(enabled: Bool) {
    keepAwakeEnabled = enabled
    sleepPreventer.update(
      keepAwake: enabled, state: timer.state, sessionType: timer.currentSessionType)
  }

  private func observeTimerForKeepAwake() {
    Publishers.CombineLatest(timer.$state, timer.$currentSessionType)
      .sink { [weak self] state, type in
        guard let self else { return }
        self.sleepPreventer.update(
          keepAwake: self.keepAwakeEnabled, state: state, sessionType: type)
      }
      .store(in: &cancellables)
  }

  static func popoverBehavior(alwaysVisible: Bool) -> NSPopover.Behavior {
    alwaysVisible ? .applicationDefined : .transient
  }

  func setPopoverBehavior(alwaysVisible: Bool) {
    popover.behavior = Self.popoverBehavior(alwaysVisible: alwaysVisible)
  }

  private func installEscapeKeyMonitor() {
    guard escapeKeyMonitor == nil else { return }
    escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
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

  func updateMenuBarStyle(_ style: MenuBarTimeStyle) {
    let wasShown = popover.isShown
    if wasShown { popover.performClose(nil) }
    menuBarStyle = style
    statusItemController.layoutMenuBar(style: style)
    updateTickMode()
    if wasShown {
      DispatchQueue.main.async { self.togglePopover() }
    }
  }

  private let popoverFocusReturn = FocusReturn()

  @objc func togglePopover() {
    guard let button = statusItemController.statusButton else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      popoverFocusReturn.remember()
      NSApp.activate(ignoringOtherApps: true)
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      // Don't start typing in the label field: Space should start the timer.
      DispatchQueue.main.async { self.popoverWindow?.makeFirstResponder(nil) }
    }
  }

  func openSettings() {
    if !popover.isShown { togglePopover() }
    DispatchQueue.main.async { self.openSettingsRequests.send() }
  }

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
    let res = NotificationResponse(actionIdentifier: response.actionIdentifier)
    DispatchQueue.main.async { [weak self] in
      switch res {
      case .timerAction(let action): self?.timer.handleNotificationAction(action)
      case .openPopover: if let self, !self.popover.isShown { self.togglePopover() }
      case .ignore: break
      }
      completionHandler()
    }
  }

  func popoverWillShow(_ notification: Notification) {
    isPopoverOpen = true
    timer.refreshStaleCycle()
    installEscapeKeyMonitor()
    updateTickMode()
    popoverModel.setPopoverVisible(true)
  }

  func popoverDidClose(_ notification: Notification) {
    isPopoverOpen = false
    removeEscapeKeyMonitor()
    updateTickMode()
    popoverModel.setPopoverVisible(false)
    // Closing the popover mid-recording would otherwise leave every shortcut off.
    if hotKeyManager.isRecording { hotKeyManager.endRecording() }
    // Give the keyboard back to the app the user was in (none when opened over the
    // break screen, which TimeMate already held).
    popoverFocusReturn.restore()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
    -> Bool
  {
    if !popover.isShown { togglePopover() }
    return true
  }
}

extension PomodoroTimer {
  /// The app's one timer, shared by the menu bar, the popover and the Shortcuts actions.
  /// Stored lengths and cycles are clamped first, so the first session runs what
  /// Settings shows.
  static let shared: PomodoroTimer = {
    let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    if !isTesting { clampStoredSettings(in: .standard) }
    return PomodoroTimer(
      history: SessionHistory(fileURL: isTesting ? nil : SessionHistory.defaultFileURL()))
  }()
}
