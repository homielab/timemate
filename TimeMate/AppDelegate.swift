//  Created by homielab.com

import AppKit
import Combine
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

  // MARK: - Properties
  private var statusItem: NSStatusItem!
  private var popover: NSPopover!
  private let timer = PomodoroTimer()
  private var hostingController: NSHostingController<AnyView>!
  private let sleepPreventer = SleepPreventer()
  private var breakOverlayController: BreakOverlayWindowController!
  @AppStorage("hideMenuBarTime") private var hideMenuBarTime = false

  // MARK: - App Lifecycle
  func applicationDidFinishLaunching(_ notification: Notification) {
    self.setDockIcon(hidden: UserDefaults.standard.hideDockIcon)
    self.setKeepAwake(enabled: UserDefaults.standard.keepAwake)

    // Register defaults
    UserDefaults.standard.register(defaults: [
      "overlayEnabled": true,
      "notificationsEnabled": true,
      "keepAwake": false,
      "hideDockIcon": true,
      "alwaysVisible": false,
      "showProgressCircle": true,
      "autoStartNextSession": true,
    ])

    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
      _, _ in
    }

    NSColorPanel.shared.showsAlpha = true

    let initialWidth = hideMenuBarTime ? 24.0 : 90.0
    statusItem = NSStatusBar.system.statusItem(withLength: initialWidth)

    let menuBarView = MenuBarView(timer: timer, hideTime: $hideMenuBarTime)
    let hostingView = NSHostingView(rootView: menuBarView)
    hostingView.frame = NSRect(x: 0, y: 0, width: initialWidth, height: NSStatusBar.system.thickness)

    statusItem.button?.subviews.forEach { $0.removeFromSuperview() }
    statusItem.button?.addSubview(hostingView)
    hostingView.frame = statusItem.button?.bounds ?? .zero

    statusItem.button?.target = self
    statusItem.button?.action = #selector(togglePopover)

    // --- Popover Setup ---
    let contentView = ContentView().environmentObject(timer).environmentObject(self)
    hostingController = NSHostingController(rootView: AnyView(contentView))
    popover = NSPopover()
    popover.behavior = .transient
    popover.contentViewController = hostingController

    // --- Initial State ---
    updatePopoverSize()
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.togglePopover()
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
    if enabled {
      sleepPreventer.enable()
    } else {
      sleepPreventer.disable()
    }
  }

  func setPopoverBehavior(alwaysVisible: Bool) {
    // Always use transient behavior to allow closing on outside clicks
    popover.behavior = .transient
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
    let hostingView = NSHostingView(rootView: menuBarView)
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
