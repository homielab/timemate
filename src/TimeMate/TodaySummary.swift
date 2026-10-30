//  Created by homielab.com

import Foundation

/// What the popover's "Today" line shows: the text, goal progress, streak and one
/// VoiceOver label. Pure value logic so the view only renders it.
struct TodaySummary: Equatable {
  /// The daily goal, `DailyGoal.off` when none is set.
  let goal: Int
  let reached: Bool
  let progress: Double
  let streak: Int
  let showsStreak: Bool
  /// "Today: 3/8 pomodoros · 75 min", or "Today: 3 pomodoros · 75 min" with no goal.
  let visibleText: String
  /// "Streak: 4 days"; empty when hidden.
  let streakText: String
  /// VoiceOver label of the goal block: today's spoken text, "goal reached", then the streak.
  let accessibilityLabel: String

  var hasGoal: Bool { goal > DailyGoal.off }

  /// `streak` is only called when a goal is on, because counting it scans the history.
  init(
    pomodoros: Int, minutes: Int, goal storedGoal: Int?, streak: () -> Int,
    bundle: Bundle = .main, locale: Locale = AppLocale.current
  ) {
    let goal = DailyGoal.sanitized(storedGoal)
    self.goal = goal
    guard goal > DailyGoal.off else {
      reached = false
      progress = 0
      self.streak = 0
      showsStreak = false
      visibleText = StatisticsText.today(
        pomodoros: pomodoros, minutes: minutes, bundle: bundle, locale: locale)
      streakText = ""
      accessibilityLabel = visibleText
      return
    }
    let streakDays = streak()
    reached = DailyGoal.isReached(completed: pomodoros, goal: goal)
    progress = DailyGoal.progress(completed: pomodoros, goal: goal)
    self.streak = streakDays
    showsStreak = DailyGoal.showsStreak(streak: streakDays, goal: goal)
    visibleText = StatisticsText.today(
      pomodoros: pomodoros, goal: goal, minutes: minutes, bundle: bundle, locale: locale)
    streakText =
      showsStreak ? StatisticsText.streak(days: streakDays, bundle: bundle, locale: locale) : ""
    accessibilityLabel = DailyGoal.accessibilityLabel(
      today: StatisticsText.spokenToday(
        pomodoros: pomodoros, goal: goal, minutes: minutes, goalReached: reached, bundle: bundle,
        locale: locale),
      streak: showsStreak ? streakText : nil)
  }
}
