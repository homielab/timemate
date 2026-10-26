//  Created by homielab.com

import SwiftUI

struct AutomationSection: View {
  @AppStorage(SettingsKey.autoStartNextSession) private var autoStartNextSession = true
  @AppStorage(SettingsKey.keepBreakScreenOpen) private var keepBreakScreenOpen = true
  @AppStorage(SettingsKey.autoStartOnLaunch) private var autoStartOnLaunch = false

  @AppStorage(SettingsKey.pauseOnSleep) private var pauseOnSleep = false

  var body: some View {
    SettingsSection(titleKey: "Automation", systemImage: "play.circle") {
      SettingsToggleRow(titleKey: "Auto-start next session", isOn: $autoStartNextSession)
        .help("Start the next session automatically when the current one ends.")
      SettingsToggleRow(
        titleKey: "Keep break screen open until continued", isOn: $keepBreakScreenOpen
      )
      .help("Keep the break overlay on screen until you continue manually.")
      SettingsToggleRow(titleKey: "Auto-start on launch", isOn: $autoStartOnLaunch)
        .help("Start a focus session automatically when the app opens.")
      SettingsToggleRow(
        titleKey: "Pause when the Mac sleeps or the screen locks", isOn: $pauseOnSleep
      )
      .help("Pause a running session when the Mac sleeps or the screen locks. Resume it yourself.")
    }
  }
}
