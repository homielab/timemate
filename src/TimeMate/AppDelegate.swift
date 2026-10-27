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
  private(set) lazy var hotKeyManager = HotKeyManager { [weak self] in self?.timer.perform($0) }
  private var cancellables = Set<AnyCancellable>()
  let openSettingsRequests = PassthroughSubject<Void, Never>()
  private var menuBarStyle = MenuBarTimeStyle.minutesSeconds

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

    if UserDefaults.standard.bool(forKey: SettingsKey.autoStartOnLaunch), timer.state == .idle {
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
      voiceOverRunning: statusItemController?.isVoiceOverRunning ?? false
    )
  }

  private func observeTimerForTickMode() {
    Publishers.CombineLatest4(
      timer.$state, timer.$currentSessionType, timer.$isBreakPostponed, timer.$isWaitingToContinue
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in self?.updateTickMode() }
    .store(in: &cancellables)

    NotificationCenter.default.publisher(
      for: UserDefaults.didChangeNotification, object: UserDefaults.standard
    )
    .sink { [weak self] _ in
      guard let self else { return }
      if Thread.isMainThread {
        self.updateTickMode()
      } else {
        DispatchQueue.main.async { self.updateTickMode() }
      }
    }
    .store(in: &cancellables)
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

  @objc func togglePopover() {
    guard let button = statusItemController.statusButton else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
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

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
    -> Bool
  {
    if !popover.isShown { togglePopover() }
    return true
  }
}

extension PomodoroTimer {
  /// The app's one timer, shared by the menu bar, the popover and the Shortcuts actions.
  static let shared = PomodoroTimer(
    history: SessionHistory(
      fileURL: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        ? nil : SessionHistory.defaultFileURL()))
}
