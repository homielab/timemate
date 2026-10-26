//  Created by homielab.com

import AppKit
import SwiftUI
import UserNotifications

struct AlertsSection: View {
  @AppStorage(SettingsKey.notificationsEnabled) private var notificationsEnabled = true
  @AppStorage(SettingsKey.breakThroughFocus) private var breakThroughFocus = true
  @AppStorage(SettingsKey.overlayEnabled) private var overlayEnabled = true
  @AppStorage(SettingsKey.overlaySkipFullscreen) private var overlaySkipFullscreen = true
  @AppStorage(SettingsKey.overlaySkipDelay) private var skipDelay =
    BreakOverlayAccessibility.defaultSkipDelay
  @AppStorage(SettingsKey.alarmSound) private var alarmSound = AlarmSound.defaultName
  /// Unset until the user picks one; the break end then sounds like the alarm.
  @AppStorage(SettingsKey.breakEndSound) private var breakEndSound: String?
  @AppStorage(SettingsKey.alarmVolume) private var alarmVolume: Double = 1.0
  @State private var notificationsDenied = false

  private var breakEndSoundBinding: Binding<String> {
    Binding(
      get: { breakEndSound ?? alarmSound },
      set: { breakEndSound = $0 }
    )
  }

  var body: some View {
    SettingsSection(titleKey: "Alerts & Sound", systemImage: "bell.fill") {
      SettingsToggleRow(titleKey: "Enable Notifications", isOn: $notificationsEnabled)
      SettingsToggleRow(titleKey: "Break through Focus", isOn: $breakThroughFocus)
        .disabled(!notificationsEnabled)
        .help(
          "Show the session-complete notification even while a Focus mode or Do Not Disturb is on."
        )
      if notificationsDenied {
        HStack {
          Text("Notifications denied in System Settings.")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer(minLength: 12)
          Button("Open System Settings") {
            if let url = URL(
              string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
            {
              NSWorkspace.shared.open(url)
            }
          }
          .buttonStyle(.link)
          .font(.caption)
        }
      }
      SettingsToggleRow(titleKey: "Enable Break Overlay", isOn: $overlayEnabled)
      SettingsToggleRow(titleKey: "Don't interrupt full-screen apps", isOn: $overlaySkipFullscreen)
        .disabled(!overlayEnabled)
        .help(
          "While the app in front is full screen, such as a presentation or video, the break screen waits until you leave it. The notification still arrives."
        )
      HStack {
        Text("Skip button delay")
        Spacer(minLength: 12)
        Text(String(format: NSLocalizedString("%d s", comment: ""), skipDelay))
          .monospacedDigit()
          .foregroundColor(.secondary)
          .frame(width: 52, alignment: .trailing)
        Stepper("", value: $skipDelay, in: BreakOverlayAccessibility.skipDelayRange)
          .labelsHidden()
          .accessibilityLabel(Text("Skip button delay"))
      }
      .help("Seconds before the Skip button appears on the break screen (0 shows it right away).")

      SoundPickerRow(
        titleKey: "Alarm Sound", previewKey: "Preview Alarm Sound", selection: $alarmSound,
        volume: alarmVolume)
      SoundPickerRow(
        titleKey: "Break End Sound", previewKey: "Preview Break End Sound",
        selection: breakEndSoundBinding, volume: alarmVolume
      )
      .help("Plays when a break ends. Until you pick one, it is the same as the alarm sound.")

      HStack(spacing: 8) {
        Image(systemName: "speaker.fill")
          .font(.system(size: 9))
          .foregroundColor(.secondary)
          .accessibilityHidden(true)
        Slider(value: $alarmVolume, in: 0.0...1.0)
          .accessibilityLabel(Text("Volume"))
        Text(verbatim: "\(Int((alarmVolume * 100).rounded()))%")
          .font(.caption)
          .monospacedDigit()
          .foregroundColor(.secondary)
          .frame(width: 30, alignment: .trailing)
      }
    }
    .onAppear(perform: refreshNotificationStatus)
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
    ) { _ in
      refreshNotificationStatus()
    }
  }

  private func refreshNotificationStatus() {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let denied = settings.authorizationStatus == .denied
      DispatchQueue.main.async { notificationsDenied = denied }
    }
  }
}

/// A sound picker ("None" or a system sound) with a button that plays the choice.
private struct SoundPickerRow: View {
  let titleKey: LocalizedStringKey
  let previewKey: LocalizedStringKey
  @Binding var selection: String
  let volume: Double

  var body: some View {
    HStack {
      Text(titleKey)
      Spacer(minLength: 12)
      Picker(selection: $selection) {
        ForEach(AlarmSound.options, id: \.self) { name in
          if name == AlarmSound.none {
            Text("None")
          } else {
            Text(verbatim: name)
          }
        }
      } label: {
        Text(titleKey)
      }
      .labelsHidden()
      .fixedSize()
      .accessibilityLabel(Text(titleKey))
      Button {
        AlarmSound.play(selection, volume: Float(volume))
      } label: {
        Image(systemName: "play.fill")
          .font(.system(size: 10, weight: .semibold))
      }
      .buttonStyle(.plain)
      .foregroundColor(.secondary)
      .disabled(selection == AlarmSound.none)
      .help(Text(previewKey))
      .accessibilityLabel(Text(previewKey))
    }
  }
}
