//  Created by homielab.com

import SwiftUI

/// All settings sections, shown below the controls when the gear is toggled.
struct SettingsView: View {
  @Binding var showProgressCircle: Bool
  @Binding var backgroundColorHex: String

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      DurationsSection()
      AutomationSection()
      KeyboardShortcutsSection()
      AlertsSection()
      AppearanceSection(
        showProgressCircle: $showProgressCircle, backgroundColorHex: $backgroundColorHex)
      SystemSection()
      StatisticsSection()
      LanguageSection()
      AboutSection()
    }
  }
}
