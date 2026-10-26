//  Created by homielab.com

import ServiceManagement
import SwiftUI
import os

struct SystemSection: View {
  @EnvironmentObject var appDelegate: AppDelegate

  // The login item registration is the source of truth; syncStartAtLoginStatus()
  // reads it into these states so register()/unregister() run only on user edits.
  @State private var startAtLogin = false
  @State private var startAtLoginNeedsApproval = false
  @State private var startAtLoginError: String?
  @AppStorage(SettingsKey.showTimerAtLogin) private var showTimerAtLogin = false
  @AppStorage(SettingsKey.hideDockIcon) private var hideDockIcon = true
  @AppStorage(SettingsKey.keepAwake) private var keepAwake = false

  var body: some View {
    SettingsSection(titleKey: "System", systemImage: "gearshape.fill") {
      SettingsToggleRow(
        titleKey: "Start at Login",
        isOn: Binding(
          get: { startAtLogin },
          set: { updateStartAtLogin($0) }
        )
      )
      .onAppear(perform: syncStartAtLoginStatus)
      .onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in
        syncStartAtLoginStatus()
      }
      if let startAtLoginError {
        HStack {
          Text(startAtLoginError)
            .font(.caption)
            .foregroundColor(.red)
          Spacer(minLength: 12)
          Button("Open System Settings") {
            try? SMAppService.openSystemSettingsLoginItems()
          }
          .buttonStyle(.link)
          .font(.caption)
        }
      }
      if startAtLoginNeedsApproval {
        HStack {
          Text("Login item needs approval in System Settings.")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer(minLength: 12)
          Button("Open System Settings") {
            try? SMAppService.openSystemSettingsLoginItems()
          }
          .buttonStyle(.link)
          .font(.caption)
        }
      }
      SettingsToggleRow(titleKey: "Show timer when started at login", isOn: $showTimerAtLogin)
        .help("Open the timer popover when TimeMate starts at login.")
      SettingsToggleRow(titleKey: "Hide Dock icon", isOn: $hideDockIcon)
        .onChange(of: hideDockIcon) { newValue in
          appDelegate.setDockIcon(hidden: newValue)
        }
      SettingsToggleRow(titleKey: "Keep Mac awake", isOn: $keepAwake)
        .help("Prevent your Mac from going to sleep during a focus session.")
        .onChange(of: keepAwake) { newValue in
          appDelegate.setKeepAwake(enabled: newValue)
        }
    }
  }

  private func updateStartAtLogin(_ enabled: Bool) {
    startAtLoginError = nil
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      Logger.app.error(
        "Could not update Start at Login: \(error.localizedDescription, privacy: .public)")
      let format =
        enabled
        ? NSLocalizedString("Could not turn on Start at Login: %@", comment: "")
        : NSLocalizedString("Could not turn off Start at Login: %@", comment: "")
      startAtLoginError = String(format: format, error.localizedDescription)
    }
    // The registration status, not the click, decides what the toggle shows.
    syncStartAtLoginStatus()
  }

  private func syncStartAtLoginStatus() {
    let state = LoginItemState(from: SMAppService.mainApp.status)
    startAtLogin = state.isOn
    startAtLoginNeedsApproval = state.needsApproval
  }
}
