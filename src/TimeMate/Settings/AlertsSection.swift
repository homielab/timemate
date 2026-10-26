//  Created by homielab.com

import AppKit
import SwiftUI
import UserNotifications

struct AlertsSection: View {
  @AppStorage(SettingsKey.notificationsEnabled) private var notificationsEnabled = true
  @AppStorage(SettingsKey.breakThroughFocus) private var breakThroughFocus = true
  @AppStorage(SettingsKey.overlayEnabled) private var overlayEnabled = true
  @AppStorage(SettingsKey.overlaySkipDelay) private var skipDelay =
    BreakOverlayAccessibility.defaultSkipDelay
  @AppStorage(SettingsKey.alarmSound) private var alarmSound = "Glass"
  @AppStorage(SettingsKey.alarmVolume) private var alarmVolume: Double = 1.0
  @State private var notificationsDenied = false

  private let soundOptions = [
    "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr",
    "Sosumi", "Submarine", "Tink",
  ]

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

      HStack {
        Text("Alarm Sound")
        Spacer(minLength: 12)
        Picker("", selection: $alarmSound) {
          ForEach(soundOptions, id: \.self) { Text($0) }
        }
        .labelsHidden()
        .fixedSize()
      }

      HStack(spacing: 8) {
        Image(systemName: "speaker.fill")
          .font(.system(size: 9))
          .foregroundColor(.secondary)
        Slider(value: $alarmVolume, in: 0.0...1.0)
          .accessibilityLabel(Text("Volume"))
        Button {
          if let sound = NSSound(named: alarmSound) {
            sound.volume = Float(alarmVolume)
            sound.play()
          }
        } label: {
          Image(systemName: "play.fill")
            .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .help("Preview Alarm Sound")

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
