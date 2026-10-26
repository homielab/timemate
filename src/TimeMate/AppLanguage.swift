//  Created by homielab.com

import Foundation

/// The language the user picked in Settings → Language, and the web page that
/// matches the language the app is shown in.
enum AppLanguage {
  static let system = "system"
  static let defaultsKey = "AppleLanguages"

  /// Picker value for a stored `AppleLanguages` list: "en", "vi", or "system"
  /// when nothing (or another language) is stored.
  static func code(fromStored languages: [String]?) -> String {
    guard let lang = languages?.first else { return system }
    if lang.hasPrefix("en") { return "en" }
    if lang.hasPrefix("vi") { return "vi" }
    return system
  }

  /// Reads the choice from the app's own defaults domain. `UserDefaults.standard`
  /// also returns the global `AppleLanguages`, so it never looks "unset".
  static func savedCode(defaults: UserDefaults = .standard, domain: String?) -> String {
    guard let domain else { return system }
    let stored = defaults.persistentDomain(forName: domain)?[defaultsKey] as? [String]
    return code(fromStored: stored)
  }

  /// "vi" for Vietnamese UIs, "en" for everything else (the web has en and vi).
  static func webLocale(preferredLocalizations: [String]) -> String {
    preferredLocalizations.first?.hasPrefix("vi") == true ? "vi" : "en"
  }

  static func aboutURL(preferredLocalizations: [String]) -> URL? {
    let locale = webLocale(preferredLocalizations: preferredLocalizations)
    return URL(string: "https://homielab.com/\(locale)/page/timemate")
  }
}
