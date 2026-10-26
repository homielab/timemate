//  Created by homielab.com

import AppKit
import SwiftUI

struct AboutSection: View {
  @State private var showingResetAlert = false

  var body: some View {
    SettingsSection(titleKey: "About & Support", systemImage: "info.circle") {
      VStack(alignment: .leading) {
        MenuItemButton(title: "About", systemImage: "info.circle") {
          if let url = URL(string: "https://homielab.com/page/timemate") {
            NSWorkspace.shared.open(url)
          }
        }

        MenuItemButton(title: "Support", systemImage: "envelope.fill") {
          if let url = URL(string: "mailto:contact@homielab.com") {
            NSWorkspace.shared.open(url)
          }
        }

        MenuItemButton(title: "Review on App Store", systemImage: "star.fill") {
          if let url = URL(
            string: "macappstore://apps.apple.com/app/id6754137356?action=write-review")
          {
            NSWorkspace.shared.open(url)
          }
        }

        #if DEBUG
          MenuItemButton(title: "Donate", systemImage: "heart.fill") {
            if let url = URL(string: "https://ko-fi.com/homielab") {
              NSWorkspace.shared.open(url)
            }
          }
        #endif

        MenuItemButton(title: "Reset All Settings", systemImage: "arrow.counterclockwise.circle") {
          showingResetAlert = true
        }

        MenuItemButton(title: "Quit", systemImage: "power") {
          NSApplication.shared.terminate(nil)
        }

        Divider().padding(.vertical, 4)

        Text(
          String(
            format: NSLocalizedString("Version %@", comment: ""),
            "\(Bundle.main.appVersion) (\(Bundle.main.appBuild))")
        )
        .font(.caption).foregroundColor(.secondary)
        .padding(.horizontal, 10)
      }
      .alert("Reset Settings?", isPresented: $showingResetAlert) {
        Button("Reset", role: .destructive) {
          resetAllSettings()
        }
        Button("Cancel", role: .cancel) {
        }
      } message: {
        Text(
          "This will restore all settings to their default values and restart the app. A running session and today's goal notification are kept. Are you sure?"
        )
      }
    }
  }
}
