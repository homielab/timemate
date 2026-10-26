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
    .contentShape(Rectangle())
    .onChange(of: [settingsVisible, showProgressCircle]) { _ in
      appDelegate.updatePopoverSize()
    }
    .onReceive(appDelegate.openSettingsRequests) { _ in
      settingsVisible = true
    }
  }
}
