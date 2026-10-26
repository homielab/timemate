//  Created by homielab.com

import Foundation

/// Statistics texts with counts. Their plural forms ("1 pomodoro" / "2 pomodoros")
/// come from `Localizable.stringsdict`.
enum StatisticsText {
  /// "Today: 3 pomodoros · 75 min"
  static func today(pomodoros: Int, minutes: Int, bundle: Bundle = .main) -> String {
    format("Today: %lld pomodoros · %lld min", bundle, pomodoros, minutes)
  }

  /// "Today: 3/8 pomodoros · 75 min", shown when a daily goal is set.
  static func today(pomodoros: Int, goal: Int, minutes: Int, bundle: Bundle = .main) -> String {
    format("Today: %1$lld/%2$lld pomodoros · %3$lld min", bundle, pomodoros, goal, minutes)
  }

  /// VoiceOver for the line above: "Today: 3 of 8 pomodoros, 75 minutes"
  static func spokenToday(pomodoros: Int, goal: Int, minutes: Int, bundle: Bundle = .main)
    -> String
  {
    format("Today: %1$lld of %2$lld pomodoros, %3$lld minutes", bundle, pomodoros, goal, minutes)
  }

  /// Notification text: "Daily goal reached: 8 pomodoros today"
  static func goalReached(goal: Int, bundle: Bundle = .main) -> String {
    format("Daily goal reached: %lld pomodoros today", bundle, goal)
  }

  /// "Goal reached on 4 of 7 days"
  static func goalDays(reached: Int, of days: Int, bundle: Bundle = .main) -> String {
    format("Goal reached on %1$lld of %2$lld days", bundle, reached, days)
  }

  /// "Week: 12 pomodoros · 300 min"
  static func week(pomodoros: Int, minutes: Int, bundle: Bundle = .main) -> String {
    format("Week: %lld pomodoros · %lld min", bundle, pomodoros, minutes)
  }

  /// "Month: 40 pomodoros · 1000 min" (the last 30 days)
  static func month(pomodoros: Int, minutes: Int, bundle: Bundle = .main) -> String {
    format("Month: %lld pomodoros · %lld min", bundle, pomodoros, minutes)
  }

  /// The totals line of a period of `days` days: "Week: …" or "Month: …".
  static func total(pomodoros: Int, minutes: Int, days: Int, bundle: Bundle = .main) -> String {
    days == SessionStatistics.monthLength
      ? month(pomodoros: pomodoros, minutes: minutes, bundle: bundle)
      : week(pomodoros: pomodoros, minutes: minutes, bundle: bundle)
  }

  /// "+3 pomodoros (+25%), −20 min vs the previous 30 days"
  static func change(
    pomodoros: Int, percent: Int, minutes: Int, days: Int, bundle: Bundle = .main
  ) -> String {
    format(
      "%1$@ pomodoros (%2$@), %3$@ min vs the previous %4$lld days", bundle,
      SessionStatistics.signedChange(pomodoros), SessionStatistics.signedChange(percent) + "%",
      SessionStatistics.signedChange(minutes), days, abs(pomodoros))
  }

  /// VoiceOver for one day: "Monday, October 20: 1 pomodoro, 25 minutes"
  /// With `goalReached`: "Monday, October 20: 8 pomodoros, 200 minutes, goal reached"
  static func spokenDay(
    _ day: String, pomodoros: Int, minutes: Int, goalReached: Bool = false,
    bundle: Bundle = .main
  ) -> String {
    let text = format("%1$@: %2$lld pomodoros, %3$lld minutes", bundle, day, pomodoros, minutes)
    return goalReached ? format("%@, goal reached", bundle, text) : text
  }

  private static func format(_ key: String, _ bundle: Bundle, _ arguments: CVarArg...) -> String {
    let format = bundle.localizedString(forKey: key, value: nil, table: nil)
    return String(format: format, locale: .current, arguments: arguments)
  }
}
