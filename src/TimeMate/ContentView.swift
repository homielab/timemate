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

  @AppStorage(SettingsKey.backgroundColorHex) private var backgroundColorHex: String = ""
  @AppStorage(SettingsKey.showProgressCircle) private var showProgressCircle = true

  var body: some View {
    VStack(spacing: 12) {
      TimerDisplayView(settingsVisible: $settingsVisible, showProgressCircle: $showProgressCircle)
      ControlButtonsView()

      if settingsVisible {
        Divider()
        ScrollView(showsIndicators: false) {
          SettingsView(
            showProgressCircle: $showProgressCircle, backgroundColorHex: $backgroundColorHex
          )
          .padding(.trailing, 8)
        }
        .frame(maxHeight: 450)
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
