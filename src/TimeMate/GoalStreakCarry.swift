//  Created by homielab.com

import Foundation

/// The part of the goal streak that lies in days the history no longer keeps.
/// When old sessions are dropped (see `SessionHistory.retentionDays`), the days
/// in a row that met each possible goal up to `throughDay` are saved here, so a
/// streak longer than the kept history still counts every day. Pure value logic.
struct GoalStreakCarry: Codable, Equatable {
  /// Start of the last day the counts cover (the newest day touched by trimming).
  let throughDay: Date
  /// `streaks[goal - 1]`: the days in a row, ending on `throughDay`, with at least
  /// `goal` pomodoros, for every goal in `DailyGoal.range`. The goal isn't saved per
  /// day, so the carry knows the answer for any goal set later.
  let streaks: [Int]

  /// The carried days for `goal`; 0 with no goal or one the carry doesn't cover.
  func streak(goal: Int) -> Int {
    guard DailyGoal.range.contains(goal), goal - 1 < streaks.count else { return 0 }
    return max(0, streaks[goal - 1])
  }

  /// The carry through `day` from `records` (which must still hold every session
  /// after `previous.throughDay` up to the end of `day`), continuing `previous`
  /// when the run of reached days goes back to it. Without `previous` the run is
  /// counted from the oldest session in `records`.
  static func advanced(
    _ previous: GoalStreakCarry?, through day: Date,
    records: [SessionHistory.Record], calendar: Calendar
  ) -> GoalStreakCarry {
    let through = calendar.startOfDay(for: day)
    var count = 0
    if let previous {
      count = calendar.dateComponents([.day], from: previous.throughDay, to: through).day ?? 0
    } else if let oldest = records.filter({ $0.kind == .focus && $0.completed }).map(\.end).min() {
      let first = calendar.startOfDay(for: oldest)
      if first <= through {
        count = (calendar.dateComponents([.day], from: first, to: through).day ?? 0) + 1
      }
    }
    let days =
      count > 0
      ? SessionStatistics.days(from: records, endingOn: through, count: count, calendar: calendar)
      : []
    let streaks = DailyGoal.range.map { goal -> Int in
      let run = days.reversed()
        .prefix { DailyGoal.isReached(completed: $0.pomodoros, goal: goal) }.count
      return run == days.count ? run + (previous?.streak(goal: goal) ?? 0) : run
    }
    return GoalStreakCarry(throughDay: through, streaks: streaks)
  }
}
