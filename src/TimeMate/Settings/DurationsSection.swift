//  Created by homielab.com

import SwiftUI

struct DurationsSection: View {
  @AppStorage(SettingsKey.focusDuration) private var focusDuration = 25
  @AppStorage(SettingsKey.shortBreakDuration) private var shortBreakDuration = 5
  @AppStorage(SettingsKey.longBreakDuration) private var longBreakDuration = 15
  @AppStorage(SettingsKey.longBreakInterval) private var longBreakInterval = 4

  var body: some View {
    SettingsSection(titleKey: "Durations", systemImage: "timer") {
      DurationRow(titleKey: "Focus", minutes: $focusDuration, step: 5)
      DurationRow(titleKey: "Short Break", minutes: $shortBreakDuration, step: 1)
      DurationRow(titleKey: "Long Break", minutes: $longBreakDuration, step: 5)
      HStack {
        Text("Cycles")
        Spacer(minLength: 12)
        Text("\(longBreakInterval)")
          .monospacedDigit()
          .foregroundColor(.secondary)
          .frame(width: 52, alignment: .trailing)
        Stepper("", value: $longBreakInterval, in: 2...8).labelsHidden()
      }
    }
  }
}

/// A session length: type any number of minutes (1–180) or use the stepper.
private struct DurationRow: View {
  let titleKey: LocalizedStringKey
  @Binding var minutes: Int
  let step: Int

  @State private var text = ""
  @FocusState private var isEditing: Bool

  private var isValid: Bool { SessionDuration.minutes(from: text) != nil }

  var body: some View {
    HStack {
      Text(titleKey)
      Spacer(minLength: 12)
      TextField("", text: $text)
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: 44)
        .foregroundColor(isValid ? .primary : .red)
        .focused($isEditing)
        .onSubmit(commit)
        .help("Enter 1–180 minutes")
        .accessibilityLabel(Text(titleKey))
      Text("min")
        .foregroundColor(.secondary)
      Stepper("", value: $minutes, in: SessionDuration.minuteRange, step: step).labelsHidden()
    }
    .onAppear { text = "\(minutes)" }
    .onChange(of: minutes) { text = "\($0)" }
    .onChange(of: isEditing) { editing in
      if !editing { commit() }
    }
  }

  /// Saves a valid entry; anything else goes back to the current value.
  private func commit() {
    if let value = SessionDuration.minutes(from: text) {
      minutes = value
    }
    text = "\(minutes)"
  }
}
