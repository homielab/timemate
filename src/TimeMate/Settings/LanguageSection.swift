//  Created by homielab.com

import SwiftUI

struct LanguageSection: View {
  @State private var selectedLanguage: String = "system"

  private var savedLanguageCode: String {
    AppLanguage.savedCode(domain: Bundle.main.bundleIdentifier)
  }

  var body: some View {
    SettingsSection(titleKey: "Language", systemImage: "globe") {
      HStack {
        Spacer(minLength: 0)
        Picker("", selection: $selectedLanguage) {
          Text("System Default").tag("system")
          Text("English").tag("en")
          Text("Vietnamese").tag("vi")
        }
        .labelsHidden()
        .accessibilityLabel("Language")
        .fixedSize()
      }
      .onAppear { self.selectedLanguage = savedLanguageCode }
      .onChange(of: selectedLanguage) { newValue in
        guard newValue != savedLanguageCode else { return }
        if newValue == "system" {
          UserDefaults.standard.removeObject(forKey: AppLanguage.defaultsKey)
        } else {
          UserDefaults.standard.set([newValue], forKey: AppLanguage.defaultsKey)
        }
        restartApp()
      }
    }
  }
}
