//  Created by homielab.com

import SwiftUI

struct AutomationSection: View {
  // Seeded from the stored switches (an unset one inherits the old single switch)
  // and written back only when the user changes it.
  @State private var autoStartBreaks = AutoStart(defaults: .standard).breaks
  @State private var autoStartFocus = AutoStart(defaults: .standard).focus
  @AppStorage(SettingsKey.keepBreakScreenOpen) private var keepBreakScreenOpen = true
  @AppStorage(SettingsKey.autoStartOnLaunch) private var autoStartOnLaunch = false

  @AppStorage(SettingsKey.pauseOnSleep) private var pauseOnSleep = false
  @AppStorage(SettingsKey.resumeOnReturn) private var resumeOnReturn = false
  @AppStorage(SettingsKey.idlePauseMinutes) private var idlePauseMinutes = IdlePausePolicy.off

  var body: some View {
    SettingsSection(titleKey: "Automation", systemImage: "play.circle") {
      SettingsToggleRow(titleKey: "Auto-start breaks", isOn: $autoStartBreaks)
        .help("Start a break automatically when a focus session ends.")
        .onChange(of: autoStartBreaks) { newValue in
          UserDefaults.standard.set(newValue, forKey: SettingsKey.autoStartBreaks)
        }
      SettingsToggleRow(titleKey: "Auto-start focus", isOn: $autoStartFocus)
        .help("Start a focus session automatically when a break ends.")
        .onChange(of: autoStartFocus) { newValue in
          UserDefaults.standard.set(newValue, forKey: SettingsKey.autoStartFocus)
        }
      Text("Auto-start focus hint")
        .font(.caption)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      SettingsToggleRow(
        titleKey: "Keep break screen open until continued", isOn: $keepBreakScreenOpen
      )
      .help("Keep the break overlay on screen until you continue manually.")
      SettingsToggleRow(titleKey: "Auto-start on launch", isOn: $autoStartOnLaunch)
        .help("Start a focus session automatically when the app opens.")
      SettingsToggleRow(
        titleKey: "Pause when the Mac sleeps or the screen locks", isOn: $pauseOnSleep
      )
      .help(
        "Pause a running focus session when the Mac sleeps or the screen locks. Resume it yourself, or turn on Resume when I'm back."
      )
      HStack {
        Text("Auto-pause when I'm away")
        Spacer(minLength: 12)
        Picker("", selection: $idlePauseMinutes) {
          ForEach(IdlePausePolicy.choices, id: \.self) { minutes in
            if minutes == IdlePausePolicy.off {
              Text("Off").tag(minutes)
            } else {
              Text("\(minutes) min").tag(minutes)
            }
          }
        }
        .labelsHidden()
        .accessibilityLabel(Text("Auto-pause when I'm away"))
        .fixedSize()
      }
      .help(
        "Pause a running focus session after this long without keyboard, mouse or trackpad input. The time away doesn't count, so your history only shows time at the desk. Watching a video without touching the Mac counts as away."
      )
      SettingsToggleRow(titleKey: "Resume when I'm back", isOn: $resumeOnReturn)
        .help(
          "Continue a session paused by sleep, the lock or being away a moment after you are back: you unlock the screen, wake the Mac or, after Auto-pause, use the keyboard, mouse or trackpad. A session you paused yourself stays paused."
        )
        .disabled(!pauseOnSleep && idlePauseMinutes == IdlePausePolicy.off)
    }
  }
}
