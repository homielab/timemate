//  Created by homielab.com

import AppKit
import Combine
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

  // MARK: - Properties
  private var statusItem: NSStatusItem!
  private var popover: NSPopover!
  private let timer = PomodoroTimer(history: AppDelegate.makeSessionHistory())
  private var hostingController: NSHostingController<AnyView>!
  private let sleepPreventer = SleepPreventer()
  private var breakOverlayController: BreakOverlayWindowController!
  private var escapeKeyMonitor: Any?
  private var keepAwakeEnabled = false
  private var cancellables = Set<AnyCancellable>()
  @AppStorage("hideMenuBarTime") private var hideMenuBarTime = false

  private static var isRunningTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }

  /// The saved session history, or an in-memory one when hosting tests so they
  /// never touch the user's statistics.
  private static func makeSessionHistory() -> SessionHistory {
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
      "overlayEnabled": true,
      "notificationsEnabled": true,
      "keepAwake": false,
      "hideDockIcon": true,
      SettingsKey.alwaysVisible: false,
      "showProgressCircle": true,
      "autoStartNextSession": true,
      "autoStartOnLaunch": false,
      "keepBreakScreenOpen": true,
    ])

    // Defaults must be registered before the first read of any setting.
    self.setDockIcon(hidden: UserDefaults.standard.hideDockIcon)
    observeTimerForKeepAwake()
    self.setKeepAwake(enabled: UserDefaults.standard.keepAwake)

    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
      _, _ in
    }

    NSColorPanel.shared.showsAlpha = true

    let initialWidth = hideMenuBarTime ? 24.0 : 90.0
    statusItem = NSStatusBar.system.statusItem(withLength: initialWidth)

    let menuBarView = MenuBarView(timer: timer, hideTime: $hideMenuBarTime)
    let hostingView = PassThroughHostingView(rootView: AnyView(menuBarView))
    hostingView.frame = NSRect(
      x: 0, y: 0, width: initialWidth, height: NSStatusBar.system.thickness)

    statusItem.button?.subviews.forEach { $0.removeFromSuperview() }
    statusItem.button?.addSubview(hostingView)
    hostingView.frame = statusItem.button?.bounds ?? .zero

    statusItem.button?.target = self
    statusItem.button?.action = #selector(togglePopover)

    // --- Popover Setup ---
    let contentView = ContentView().environmentObject(timer).environmentObject(self)
    hostingController = NSHostingController(rootView: AnyView(contentView))
    popover = NSPopover()
    popover.behavior = Self.popoverBehavior(
      alwaysVisible: UserDefaults.standard.bool(forKey: SettingsKey.alwaysVisible))
    popover.contentViewController = hostingController
    installEscapeKeyMonitor()

    // --- Initial State ---
    updatePopoverSize()
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.togglePopover()
    }

    // --- Auto-start Timer ---
    if UserDefaults.standard.bool(forKey: "autoStartOnLaunch") {
      timer.startTimer()
    }

    // --- Break Overlay ---
    breakOverlayController = BreakOverlayWindowController(timer: timer)
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
    escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, event.keyCode == 53, self.popover.isShown,
        event.window === self.popover.contentViewController?.view.window
      else { return event }
      self.popover.performClose(nil)
      return nil
    }
  }

  func updateMenuBarWidth(hideTime: Bool) {
    let newWidth = hideTime ? 24.0 : 90.0
    let wasShown = popover.isShown

    // Close popover if shown to reposition it
    if wasShown {
      popover.performClose(nil)
    }

    statusItem.length = newWidth

    // Recreate the menu bar view to force immediate refresh
    let menuBarView = MenuBarView(timer: timer, hideTime: $hideMenuBarTime)
    let hostingView = PassThroughHostingView(rootView: AnyView(menuBarView))
    hostingView.frame = NSRect(x: 0, y: 0, width: newWidth, height: NSStatusBar.system.thickness)

    statusItem.button?.subviews.forEach { $0.removeFromSuperview() }
    statusItem.button?.addSubview(hostingView)
    hostingView.frame = statusItem.button?.bounds ?? .zero

    // Reopen popover if it was shown
    if wasShown {
      DispatchQueue.main.async {
        self.togglePopover()
      }
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
  @Binding var hideTime: Bool

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
    .frame(width: hideTime ? 24 : 90, height: NSStatusBar.system.thickness, alignment: .center)
  }
}
