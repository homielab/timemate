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
        .help("Prevent your Mac from going to sleep.")
        .onChange(of: keepAwake) { newValue in
          appDelegate.setKeepAwake(enabled: newValue)
        }
    }
  }

  private func updateStartAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      Logger.app.error(
        "Could not update Start at Login: \(error.localizedDescription, privacy: .public)")
    }
    syncStartAtLoginStatus()
  }

  private func syncStartAtLoginStatus() {
    let status = SMAppService.mainApp.status
    startAtLogin = (status == .enabled || status == .requiresApproval)
    startAtLoginNeedsApproval = (status == .requiresApproval)
  }
}
