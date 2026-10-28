//  Created by homielab.com

import SwiftUI

struct DurationsSection: View {
  @AppStorage(SettingsKey.focusDuration) private var focusDuration = 25
  @AppStorage(SettingsKey.shortBreakDuration) private var shortBreakDuration = 5
  @AppStorage(SettingsKey.longBreakDuration) private var longBreakDuration = 15
  @AppStorage(SettingsKey.longBreakInterval) private var longBreakInterval =
    SessionCycle.defaultInterval

  var body: some View {
    SettingsSection(titleKey: "Durations", systemImage: "timer") {
      DurationRow(
        titleKey: "Focus", stepperLabelKey: "Focus minutes", minutes: $focusDuration, step: 5)
      DurationRow(
        titleKey: "Short Break", stepperLabelKey: "Short break minutes",
        minutes: $shortBreakDuration, step: 1)
      DurationRow(
        titleKey: "Long Break", stepperLabelKey: "Long break minutes",
        minutes: $longBreakDuration, step: 5)
      HStack {
        Text("Cycles")
        Spacer(minLength: 12)
        Text(verbatim: "\(longBreakInterval)")
          .monospacedDigit()
          .foregroundColor(.secondary)
          .frame(width: 52, alignment: .trailing)
        Stepper("", value: $longBreakInterval, in: SessionCycle.settingsRange)
          .labelsHidden()
          .accessibilityLabel(Text("Cycles"))
          .accessibilityValue(Text(verbatim: "\(longBreakInterval)"))
      }
    }
  }
}

/// A session length: type any number of minutes (1–180) or use the stepper.
private struct DurationRow: View {
  let titleKey: LocalizedStringKey
  /// VoiceOver name of the stepper, e.g. "Focus minutes".
  let stepperLabelKey: LocalizedStringKey
  @Binding var minutes: Int
  let step: Int

  @State private var text = ""
  @FocusState private var isEditing: Bool

  /// Why the typed text can't be saved, `nil` when it is valid.
  private var problem: SessionDuration.Problem? { SessionDuration.validationHint(for: text) }

  var body: some View {
    HStack {
      Text(titleKey)
      Spacer(minLength: 12)
      TextField("", text: $text)
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: 44)
        .foregroundColor(problem == nil ? .primary : .red)
        .focused($isEditing)
        .onSubmit(commit)
        .help(problem.map { LocalizedStringKey($0.rawValue) } ?? "Enter 1–180 minutes")
        .accessibilityLabel(Text(titleKey))
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
      // Not only colour: a warning sign marks an entry that won't be saved.
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundColor(.orange)
        .opacity(problem == nil ? 0 : 1)
        .help(problem.map { LocalizedStringKey($0.rawValue) } ?? "")
        .accessibilityHidden(true)
      Text("min")
        .foregroundColor(.secondary)
      Stepper("", value: $minutes, in: SessionDuration.minuteRange, step: step)
        .labelsHidden()
        .accessibilityLabel(Text(stepperLabelKey))
        .accessibilityValue(Text(verbatim: "\(minutes)"))
    }
    .onAppear { text = "\(minutes)" }
    .onChange(of: minutes) { text = "\($0)" }
    .onChange(of: isEditing) { editing in
      if !editing { commit() }
    }
  }

  /// The typed text, plus why it is invalid, so VoiceOver reads what is wrong.
  private var accessibilityValue: Text {
    guard let problem else { return Text(verbatim: text) }
    return Text(verbatim: "\(text), ") + Text(LocalizedStringKey(problem.rawValue))
  }

  /// Valid: the allowed range. Invalid: leaving the field keeps the saved value.
  private var accessibilityHint: Text {
    guard problem != nil else { return Text("Enter 1–180 minutes") }
    return Text("Not saved. Leaving the field keeps \(minutes) minutes.")
  }

  /// Saves a valid entry; anything else goes back to the current value.
  private func commit() {
    if let value = SessionDuration.minutes(from: text) {
      minutes = value
    }
    text = "\(minutes)"
  }
}
