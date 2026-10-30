import Foundation

/// The locale for dates and numbers the app formats itself: the app's language (which the
/// user can set apart from the system's) with the system's region and 12/24-hour choice.
enum AppLocale {
  static var current: Locale {
    make(language: Bundle.main.preferredLocalizations.first ?? "en", base: .current)
  }

  /// `language` with `base`'s region and hour cycle, e.g. "en" on a Mac set to Germany and
  /// 24-hour time gives "09:00 – 10:00", not "9 – 10 AM".
  static func make(language: String, base: Locale) -> Locale {
    var components = Locale.Components(locale: base)
    components.languageComponents = Locale.Language.Components(identifier: language)
    if components.languageComponents.region == nil {
      components.languageComponents.region = base.region
    }
    components.hourCycle = base.hourCycle
    return Locale(components: components)
  }
}
