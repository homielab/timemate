//  Created by homielab.com

import Foundation

/// Statistics texts with counts. Their plural forms ("1 pomodoro" / "2 pomodoros")
/// come from `Localizable.stringsdict`.
enum StatisticsText {
  /// "Today: 3 pomodoros · 75 min"
  static func today(pomodoros: Int, minutes: Int, bundle: Bundle = .main, locale: Locale = .current)
    -> String
  {
    format("Today: %lld pomodoros · %lld min", bundle, locale, pomodoros, minutes)
  }

  /// "Today: 3/8 pomodoros · 75 min", shown when a daily goal is set.
  static func today(
    pomodoros: Int, goal: Int, minutes: Int, bundle: Bundle = .main, locale: Locale = .current
  ) -> String {
    format("Today: %1$lld/%2$lld pomodoros · %3$lld min", bundle, locale, pomodoros, goal, minutes)
  }

  /// VoiceOver for the line above: "Today: 3 of 8 pomodoros, 75 minutes"
  /// With `goalReached`: "Today: 8 of 8 pomodoros, 200 minutes, goal reached"
  static func spokenToday(
    pomodoros: Int, goal: Int, minutes: Int, goalReached: Bool = false, bundle: Bundle = .main,
    locale: Locale = .current
  ) -> String {
    let text = format(
      "Today: %1$lld of %2$lld pomodoros, %3$lld minutes", bundle, locale, pomodoros, goal, minutes)
    return goalReached ? format("%@, goal reached", bundle, locale, text) : text
  }

  /// Notification text: "Daily goal reached: 8 pomodoros today"
  static func goalReached(goal: Int, bundle: Bundle = .main, locale: Locale = .current) -> String {
    format("Daily goal reached: %lld pomodoros today", bundle, locale, goal)
  }

  /// "Goal reached on 4 of 7 days"
  static func goalDays(
    reached: Int, of days: Int, bundle: Bundle = .main, locale: Locale = .current
  ) -> String {
    format("Goal reached on %1$lld of %2$lld days", bundle, locale, reached, days)
  }

  /// "Best: 12 days in the last 90 days": the longest goal streak kept.
  static func bestStreak(days: Int, bundle: Bundle = .main, locale: Locale = .current) -> String {
    format("Best: %lld days in the last 90 days", bundle, locale, days)
  }

  /// "Streak: 3 days": consecutive days that met the daily goal.
  static func streak(days: Int, bundle: Bundle = .main, locale: Locale = .current) -> String {
    format("Streak: %lld days", bundle, locale, days)
  }

  /// "Week: 12 pomodoros · 300 min"
  static func week(pomodoros: Int, minutes: Int, bundle: Bundle = .main, locale: Locale = .current)
    -> String
  {
    format("Week: %lld pomodoros · %lld min", bundle, locale, pomodoros, minutes)
  }

  /// "Month: 40 pomodoros · 1000 min" (the last 30 days)
  static func month(pomodoros: Int, minutes: Int, bundle: Bundle = .main, locale: Locale = .current)
    -> String
  {
    format("Month: %lld pomodoros · %lld min", bundle, locale, pomodoros, minutes)
  }

  /// The totals line of a period of `days` days: "Week: …" or "Month: …".
  static func total(
    pomodoros: Int, minutes: Int, days: Int, bundle: Bundle = .main, locale: Locale = .current
  ) -> String {
    days == SessionStatistics.monthLength
      ? month(pomodoros: pomodoros, minutes: minutes, bundle: bundle, locale: locale)
      : week(pomodoros: pomodoros, minutes: minutes, bundle: bundle, locale: locale)
  }

  /// "Daily average: 35 min"
  static func dailyAverage(minutes: Int, bundle: Bundle = .main, locale: Locale = .current)
    -> String
  {
    format("Daily average: %lld min", bundle, locale, minutes)
  }

  /// VoiceOver for the line above: "Daily average: 35 minutes"
  static func spokenDailyAverage(
    minutes: Int, bundle: Bundle = .main, locale: Locale = .current
  ) -> String {
    format("Daily average: %lld minutes", bundle, locale, minutes)
  }

  /// "Best day: Mon 20 · 8 pomodoros · 200 min"
  static func bestDay(
    _ day: String, pomodoros: Int, minutes: Int, bundle: Bundle = .main,
    locale: Locale = .current
  ) -> String {
    format(
      "Best day: %1$@ · %2$lld pomodoros · %3$lld min", bundle, locale, day, pomodoros, minutes)
  }

  /// VoiceOver for the line above: "Best day: Monday, October 20: 8 pomodoros, 200 minutes"
  static func spokenBestDay(
    _ day: String, pomodoros: Int, minutes: Int, bundle: Bundle = .main,
    locale: Locale = .current
  ) -> String {
    format(
      "Best day: %@", bundle, locale,
      spokenDay(day, pomodoros: pomodoros, minutes: minutes, bundle: bundle, locale: locale))
  }

  /// "+3 pomodoros (+25%), −20 min vs the previous 30 days"
  static func change(
    pomodoros: Int, percent: Int, minutes: Int, days: Int, bundle: Bundle = .main,
    locale: Locale = .current
  ) -> String {
    format(
      "%1$@ pomodoros (%2$@), %3$@ min vs the previous %4$lld days", bundle, locale,
      SessionStatistics.signedChange(pomodoros), SessionStatistics.signedChange(percent) + "%",
      SessionStatistics.signedChange(minutes), days, abs(pomodoros))
  }

  /// VoiceOver for one day: "Monday, October 20: 1 pomodoro, 25 minutes"
  /// With `goalReached`: "Monday, October 20: 8 pomodoros, 200 minutes, goal reached"
  static func spokenDay(
    _ day: String, pomodoros: Int, minutes: Int, goalReached: Bool = false,
    bundle: Bundle = .main, locale: Locale = .current
  ) -> String {
    let text = format(
      "%1$@: %2$lld pomodoros, %3$lld minutes", bundle, locale, day, pomodoros, minutes)
    return goalReached ? format("%@, goal reached", bundle, locale, text) : text
  }

  /// VoiceOver for one label row: "Writing, 50 minutes"
  static func spokenLabel(
    _ name: String, minutes: Int, bundle: Bundle = .main, locale: Locale = .current
  ) -> String {
    format("%1$@, %2$lld minutes", bundle, locale, name, minutes)
  }

  /// "Delete the focus session “Email” (2:05 PM – 2:30 PM, 25 min)?": the
  /// question before "Undo Last Session"; `label` is "No label" when empty.
  static func undoLastSession(
    label: String, timeRange: String, minutes: Int, bundle: Bundle = .main,
    locale: Locale = .current
  ) -> String {
    format(
      "Delete the focus session “%1$@” (%2$@, %3$lld min)? Totals, streak and charts are updated.",
      bundle, locale, label, timeRange, minutes)
  }

  /// "Most focused: 9 – 10 AM": the hour range with the most focus time.
  static func mostFocused(_ hours: String, bundle: Bundle = .main, locale: Locale = .current)
    -> String
  {
    format("Most focused: %@", bundle, locale, hours)
  }

  static func localized(_ key: String, bundle: Bundle = .main) -> String {
    bundle.localizedString(forKey: key, value: nil, table: nil)
  }

  private static func format(
    _ key: String, _ bundle: Bundle, _ locale: Locale, _ arguments: CVarArg...
  ) -> String {
    let format = bundle.localizedString(forKey: key, value: nil, table: nil)
    return String(format: format, locale: locale, arguments: arguments)
  }
}
