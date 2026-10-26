//  Created by homielab.com

import Foundation

/// Completed focus sessions grouped by local calendar day. Pure value logic so
/// it can be tested without the UI or the saved history file.
enum SessionStatistics {
  /// Pomodoros and focus time of one calendar day.
  struct Day: Equatable {
    /// Start of the day in the calendar's time zone.
    let date: Date
    let pomodoros: Int
    let focusSeconds: TimeInterval

    var focusMinutes: Int { Int((focusSeconds / 60).rounded()) }
  }

  /// Sum of several days. Minutes add up the rounded minutes of each day, so the
  /// total always matches the rows shown above it.
  struct Totals: Equatable {
    let pomodoros: Int
    let focusMinutes: Int

    init(pomodoros: Int, focusMinutes: Int) {
      self.pomodoros = pomodoros
      self.focusMinutes = focusMinutes
    }

    init(_ days: [Day]) {
      pomodoros = days.reduce(0) { $0 + $1.pomodoros }
      focusMinutes = days.reduce(0) { $0 + $1.focusMinutes }
    }
  }

  /// The last `length` days (oldest first, today last) and the same number of
  /// days before them.
  struct Period: Equatable {
    let days: [Day]
    let previousDays: [Day]

    var length: Int { days.count }
    var totals: Totals { Totals(days) }
    var previousTotals: Totals { Totals(previousDays) }
  }

  /// Lengths the user can pick in Settings → Statistics.
  static let weekLength = 7
  static let monthLength = 30
  static let periodLengths = [weekLength, monthLength]

  /// A stored length that isn't one of `periodLengths` falls back to a week.
  static func sanitizedLength(_ stored: Int?) -> Int {
    guard let stored, periodLengths.contains(stored) else { return weekLength }
    return stored
  }

  /// `count` consecutive days ending with the day that contains `today`, oldest
  /// first. Days without completed focus sessions have zero pomodoros.
  static func days(
    from records: [SessionHistory.Record], endingOn today: Date, count: Int,
    calendar: Calendar
  ) -> [Day] {
    guard count > 0 else { return [] }
    let lastDay = calendar.startOfDay(for: today)
    var byDay: [Date: (pomodoros: Int, seconds: TimeInterval)] = [:]
    for record in records where record.kind == .focus && record.completed {
      let day = calendar.startOfDay(for: record.end)
      let current = byDay[day] ?? (0, 0)
      byDay[day] = (current.pomodoros + 1, current.seconds + record.duration)
    }
    return (0..<count).reversed().compactMap { offset in
      guard let day = calendar.date(byAdding: .day, value: -offset, to: lastDay) else {
        return nil
      }
      let start = calendar.startOfDay(for: day)
      let totals = byDay[start] ?? (0, 0)
      return Day(date: start, pomodoros: totals.pomodoros, focusSeconds: totals.seconds)
    }
  }

  /// The `length` days ending with the day of `today` and the `length` days
  /// before them. Both are counted by calendar day, so a daylight-saving change
  /// inside the range doesn't shift or drop a day.
  static func period(
    from records: [SessionHistory.Record], today: Date, length: Int, calendar: Calendar
  ) -> Period {
    let length = max(1, length)
    let both = days(from: records, endingOn: today, count: length * 2, calendar: calendar)
    return Period(days: Array(both.suffix(length)), previousDays: Array(both.prefix(length)))
  }

  static func week(
    from records: [SessionHistory.Record], today: Date, calendar: Calendar
  ) -> Period {
    period(from: records, today: today, length: weekLength, calendar: calendar)
  }

  /// Every day from the oldest record (at least `minimumDays` back) through
  /// today, for the CSV export.
  static func allDays(
    from records: [SessionHistory.Record], today: Date, minimumDays: Int, calendar: Calendar
  ) -> [Day] {
    let lastDay = calendar.startOfDay(for: today)
    var count = max(1, minimumDays)
    if let oldest = records.map(\.end).min() {
      let firstDay = calendar.startOfDay(for: oldest)
      let span = calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0
      count = max(count, span + 1)
    }
    return days(from: records, endingOn: today, count: count, calendar: calendar)
  }

  /// How many of `days` met a daily goal (0 with no goal).
  static func daysReachingGoal(_ days: [Day], goal: Int) -> Int {
    days.filter { DailyGoal.isReached(completed: $0.pomodoros, goal: goal) }.count
  }

  /// `date,pomodoros,minutes` with one row per day, dates as `yyyy-MM-dd` in the
  /// calendar's time zone, lines ending in CRLF (RFC 4180). With a daily goal
  /// (`goal` > 0) a `goal_reached` column says 1 or 0 for each day.
  static func csv(for days: [Day], calendar: Calendar, goal: Int = DailyGoal.off) -> String {
    let withGoal = goal > DailyGoal.off
    var lines = [withGoal ? "date,pomodoros,minutes,goal_reached" : "date,pomodoros,minutes"]
    for day in days {
      let parts = calendar.dateComponents([.year, .month, .day], from: day.date)
      let date = String(
        format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
      var line = "\(date),\(day.pomodoros),\(day.focusMinutes)"
      if withGoal {
        line += DailyGoal.isReached(completed: day.pomodoros, goal: goal) ? ",1" : ",0"
      }
      lines.append(line)
    }
    return lines.joined(separator: "\r\n") + "\r\n"
  }

  /// The change from `previous` to `current` in whole percent (rounded), or nil
  /// when there is nothing to compare with (`previous` is 0 or less).
  static func percentChange(current: Int, previous: Int) -> Int? {
    guard previous > 0 else { return nil }
    return Int((Double(current - previous) / Double(previous) * 100).rounded())
  }

  /// "+3", "−2" (minus sign) or "0" for the change against the previous period.
  static func signedChange(_ value: Int) -> String {
    if value > 0 { return "+\(value)" }
    if value < 0 { return "\u{2212}\(-value)" }
    return "0"
  }
}

extension SessionHistory {
  /// The last `days` days and the same number before them, by the history's calendar.
  func statistics(days: Int) -> SessionStatistics.Period {
    SessionStatistics.period(
      from: records, today: currentDate, length: days, calendar: calendar)
  }

  /// The CSV export, with the `goal_reached` column when `goal` is set: the last
  /// `days` days, or every kept day (at least `retentionDays`) without `days`.
  func statisticsCSV(days: Int? = nil, goal: Int = DailyGoal.off) -> String {
    let rows: [SessionStatistics.Day]
    if let days {
      rows = SessionStatistics.days(
        from: records, endingOn: currentDate, count: max(1, days), calendar: calendar)
    } else {
      rows = SessionStatistics.allDays(
        from: records, today: currentDate, minimumDays: Self.retentionDays, calendar: calendar)
    }
    return SessionStatistics.csv(for: rows, calendar: calendar, goal: goal)
  }
}
