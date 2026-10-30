//  Created by homielab.com

import Foundation

/// The number of pomodoros the user wants to finish each day. Zero turns the
/// goal off. Pure value logic so it can be tested without the UI.
enum DailyGoal {
  /// The stored value when no goal is set.
  static let off = 0
  /// Values the Settings stepper offers; `off` sits just below.
  static let range = 1...24

  /// The stored goal clamped to `off` or `range`; nil (never set) means off.
  static func sanitized(_ stored: Int?) -> Int {
    guard let stored, stored > off else { return off }
    return min(stored, range.upperBound)
  }

  /// Fraction of the goal done, 0…1; always 0 with no goal.
  static func progress(completed: Int, goal: Int) -> Double {
    guard goal > off else { return 0 }
    return min(1, Double(max(0, completed)) / Double(goal))
  }

  /// Whether `completed` pomodoros meet a goal that is turned on.
  static func isReached(completed: Int, goal: Int) -> Bool {
    goal > off && completed >= goal
  }

  /// True only for the session that takes the day's count up to the goal.
  static func justReached(before: Int, after: Int, goal: Int) -> Bool {
    !isReached(completed: before, goal: goal) && isReached(completed: after, goal: goal)
  }

  /// How long after its end a session from an earlier day may still notify that
  /// it reached that day's goal (the Mac woke or the app ticked after midnight).
  static let lateNotificationWindow: TimeInterval = 60 * 60

  /// Whether the "goal reached" notification already went out on `today`'s day for
  /// `goal`; a raised goal (or a cleared flag) notifies again.
  static func wasNotified(
    on lastNotified: Date?, goal: Int? = nil, notifiedGoal: Int? = nil, today: Date,
    calendar: Calendar
  ) -> Bool {
    guard let lastNotified, calendar.isDate(lastNotified, inSameDayAs: today) else { return false }
    // A date saved without its goal (older versions) blocks the whole day.
    guard let goal, let notifiedGoal else { return true }
    return goal == notifiedGoal
  }

  /// Whether the popover shows the streak line: a goal is on and at least one day is in the streak.
  static func showsStreak(streak: Int, goal: Int) -> Bool {
    goal > off && streak >= 1
  }

  /// One VoiceOver label for the progress block: today's text, then the streak when shown.
  static func accessibilityLabel(today: String, streak: String?) -> String {
    guard let streak else { return today }
    return today + ", " + streak
  }
}
