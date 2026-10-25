//  Created by homielab.com

import SwiftUI

struct StatisticsSection: View {
  @EnvironmentObject var model: PopoverTimerModel
  @State private var showingResetAlert = false

  var body: some View {
    SettingsSection(titleKey: "Statistics", systemImage: "chart.bar.fill") {
      MenuItemButton(title: "Reset Statistics", systemImage: "trash") {
        showingResetAlert = true
      }
      .alert("Reset Statistics?", isPresented: $showingResetAlert) {
        Button("Reset", role: .destructive) {
          model.timer.history.reset()
        }
        Button("Cancel", role: .cancel) {
        }
      } message: {
        Text("This will delete the history of completed sessions. Are you sure?")
      }
    }
  }
}
