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

  // MARK: - App Lifecycle
  func applicationDidFinishLaunching(_ notification: Notification) {
    self.setDockIcon(hidden: UserDefaults.standard.hideDockIcon)
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
      _, _ in
    }

    NSColorPanel.shared.showsAlpha = true

    statusItem = NSStatusBar.system.statusItem(withLength: 90)

    let menuBarView = MenuBarView(timer: timer)
    let hostingView = NSHostingView(rootView: menuBarView)
    hostingView.frame = NSRect(x: 0, y: 0, width: 90, height: NSStatusBar.system.thickness)

    statusItem.view = hostingView

    let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(togglePopover))
    hostingView.addGestureRecognizer(clickGesture)

    // --- Popover Setup ---
    let contentView = ContentView().environmentObject(timer).environmentObject(self)
    hostingController = NSHostingController(rootView: AnyView(contentView))
    popover = NSPopover()
    popover.behavior = UserDefaults.standard.alwaysVisible ? .applicationDefined : .transient
    popover.contentViewController = hostingController

    // --- Initial State ---
    updatePopoverSize()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.togglePopover()
    }
  }

  func updatePopoverSize() {
    DispatchQueue.main.async {
      self.popover.contentSize = self.hostingController.view.fittingSize
    }
  }

  private func setDockIcon(hidden: Bool) {
    NSApp.setActivationPolicy(hidden ? .accessory : .regular)
  }

  @objc func togglePopover() {
    guard let view = statusItem.view else { return }

    if popover.isShown {
      popover.performClose(nil)
    } else {
      popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
      popover.contentViewController?.view.window?.becomeKey()
    }
  }
}

private struct MenuBarView: View {
  @ObservedObject var timer: PomodoroTimer

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

      Text(timer.timeRemaining.toMinuteSecondString())
        .font(.system(size: NSFont.systemFontSize + 1, design: .monospaced).weight(.bold))
    }
    .padding(.horizontal, 8)
    .frame(width: 90, height: NSStatusBar.system.thickness, alignment: .center)
    .foregroundColor(foregroundColor)
    .background(
      RoundedRectangle(cornerRadius: 4)
        .fill(timer.state == .active ? accentColor : .clear)
    )
  }
}
