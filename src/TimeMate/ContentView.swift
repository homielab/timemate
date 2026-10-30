//  Created by homielab.com

import SwiftUI

/// The popover: timer display and controls, with the settings below when the
/// gear is toggled. Sub-views live in `Views/`, settings sections in `Settings/`.
struct ContentView: View {
  // The popover observes the timer through `PopoverTimerModel`: only the
  // countdown views re-render each second, and only while the popover is open.
  @EnvironmentObject var model: PopoverTimerModel
  @EnvironmentObject var appDelegate: AppDelegate
  @State private var settingsVisible = false
  @State private var spaceMonitor: Any?
  @State private var topHeight: CGFloat = 0
  @State private var visibleHeight = NSScreen.main?.visibleFrame.height

  @AppStorage(SettingsKey.backgroundColorHex) private var backgroundColorHex: String = ""
  @AppStorage(SettingsKey.showProgressCircle) private var showProgressCircle = true

  var body: some View {
    VStack(spacing: 12) {
      VStack(spacing: 12) {
        TimerDisplayView(settingsVisible: $settingsVisible, showProgressCircle: $showProgressCircle)
        ControlButtonsView()
      }
      .background(
        GeometryReader { proxy in
          Color.clear.onAppear { topHeight = proxy.size.height }
            .onChange(of: proxy.size.height) { topHeight = $0 }
        })

      if settingsVisible {
        Divider()
        ScrollView(showsIndicators: false) {
          SettingsView(
            showProgressCircle: $showProgressCircle, backgroundColorHex: $backgroundColorHex
          )
          .padding(.trailing, 8)
        }
        .frame(
          maxHeight: PopoverLayout.settingsHeight(
            visibleHeight: visibleHeight, topHeight: topHeight + 32 + 12))
      }
    }
    .padding()
    .frame(minWidth: 280)
    .background(Color(hex: backgroundColorHex) ?? .clear)
    // Semantic text and control colors follow the custom background, not the system
    // appearance, so a white background in Dark Mode still gets dark text.
    .transformEnvironment(\.colorScheme) { scheme in
      if let dark = NSColor.prefersDarkText(onBackgroundHex: backgroundColorHex) {
        scheme = dark ? .light : .dark
      }
    }
    .contentShape(Rectangle())
    .onChange(of: [settingsVisible, showProgressCircle]) { _ in
      appDelegate.updatePopoverSize()
    }
    // Fit the settings to the screen the popover opens on, also after a display change.
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
    ) { _ in
      visibleHeight = NSScreen.main?.visibleFrame.height
      appDelegate.updatePopoverSize()
    }
    .onAppear { visibleHeight = NSScreen.main?.visibleFrame.height }
    // The label field shows only in focus sessions.
    .onChange(of: model.currentSessionType) { _ in
      appDelegate.updatePopoverSize()
    }
    .onReceive(appDelegate.openSettingsRequests) { _ in
      settingsVisible = true
    }
    .onAppear(perform: installSpaceMonitor)
    .onDisappear(perform: removeSpaceMonitor)
  }

  /// Space = Start/Pause while the popover is key and nothing else wants the key.
  private func installSpaceMonitor() {
    guard spaceMonitor == nil else { return }
    spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [model, appDelegate] event in
      guard let window = event.window, window === appDelegate.popoverWindow,
        PopoverShortcuts.spaceStartsOrPauses(
          keyCode: event.keyCode, modifiers: event.modifierFlags,
          firstResponder: window.firstResponder)
      else { return event }
      model.performMainAction()
      return nil
    }
  }

  private func removeSpaceMonitor() {
    if let monitor = spaceMonitor { NSEvent.removeMonitor(monitor) }
    spaceMonitor = nil
  }
}
