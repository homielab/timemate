//  Created by homielab.com

import SwiftUI

struct LanguageSection: View {
  @State private var selectedLanguage: String = "system"

  private var savedLanguageCode: String {
    guard let languages = UserDefaults.standard.stringArray(forKey: "AppleLanguages"),
      let lang = languages.first
    else { return "system" }
    if lang.hasPrefix("en") { return "en" }
    if lang.hasPrefix("vi") { return "vi" }
    return "system"
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
        .fixedSize()
      }
      .onAppear { self.selectedLanguage = savedLanguageCode }
      .onChange(of: selectedLanguage) { newValue in
        guard newValue != savedLanguageCode else { return }
        if newValue == "system" {
          UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
          UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
        }
        restartApp()
      }
    }
  }
}
