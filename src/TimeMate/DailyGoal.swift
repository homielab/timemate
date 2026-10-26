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

  /// Whether the "goal reached" notification already went out on `today`'s day.
  static func wasNotified(on lastNotified: Date?, today: Date, calendar: Calendar) -> Bool {
    guard let lastNotified else { return false }
    return calendar.isDate(lastNotified, inSameDayAs: today)
  }
}
