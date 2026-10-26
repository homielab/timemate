//  Created by homielab.com

import Foundation

/// Statistics texts with counts. Their plural forms ("1 pomodoro" / "2 pomodoros")
/// come from `Localizable.stringsdict`.
enum StatisticsText {
  /// "Today: 3 pomodoros · 75 min"
  static func today(pomodoros: Int, minutes: Int, bundle: Bundle = .main) -> String {
    format("Today: %lld pomodoros · %lld min", bundle, pomodoros, minutes)
  }

  /// "Week: 12 pomodoros · 300 min"
  static func week(pomodoros: Int, minutes: Int, bundle: Bundle = .main) -> String {
    format("Week: %lld pomodoros · %lld min", bundle, pomodoros, minutes)
  }

  /// "+3 pomodoros, −20 min vs the previous 7 days"
  static func change(pomodoros: Int, minutes: Int, bundle: Bundle = .main) -> String {
    format(
      "%1$@ pomodoros, %2$@ min vs the previous 7 days", bundle,
      SessionStatistics.signedChange(pomodoros), SessionStatistics.signedChange(minutes),
      abs(pomodoros))
  }

  /// VoiceOver for one day: "Monday, October 20: 1 pomodoro, 25 minutes"
  static func spokenDay(_ day: String, pomodoros: Int, minutes: Int, bundle: Bundle = .main)
    -> String
  {
    format("%1$@: %2$lld pomodoros, %3$lld minutes", bundle, day, pomodoros, minutes)
  }

  private static func format(_ key: String, _ bundle: Bundle, _ arguments: CVarArg...) -> String {
    let format = bundle.localizedString(forKey: key, value: nil, table: nil)
    return String(format: format, locale: .current, arguments: arguments)
  }
}
