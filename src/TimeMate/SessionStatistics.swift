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

  /// Focus time of one label over a period; `label` is nil for sessions without one.
  struct LabelTotal: Equatable {
    let label: String?
    let pomodoros: Int
    let focusSeconds: TimeInterval

    var focusMinutes: Int { Int((focusSeconds / 60).rounded()) }
  }

  /// Completed focus sessions of the last `length` days (the window of `period`),
  /// grouped by label compared ignoring case; the newest spelling is kept. Sessions
  /// without a label form one group with a nil label. Longest first; on a tie by label,
  /// the group without a label last, so the order doesn't jump between redraws.
  static func labelTotals(
    from records: [SessionHistory.Record], today: Date, length: Int, calendar: Calendar
  ) -> [LabelTotal] {
    let lastDay = calendar.startOfDay(for: today)
    guard
      let firstDay = calendar.date(byAdding: .day, value: -(max(1, length) - 1), to: lastDay),
      let end = calendar.date(byAdding: .day, value: 1, to: lastDay)
    else { return [] }
    let start = calendar.startOfDay(for: firstDay)

    struct Group {
      var label: String?
      var newest: Date
      var pomodoros = 0
      var seconds: TimeInterval = 0
    }
    var groups: [String: Group] = [:]
    for record in records
    where record.kind == .focus && record.completed && record.end >= start && record.end < end {
      let label = SessionLabel.normalized(record.label)
      let key = label?.lowercased() ?? ""
      var group = groups[key] ?? Group(label: label, newest: record.end)
      if record.end > group.newest {
        group.newest = record.end
        group.label = label
      }
      group.pomodoros += 1
      group.seconds += record.duration
      groups[key] = group
    }
    return groups.values
      .sorted { lhs, rhs in
        if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
        guard let left = lhs.label else { return false }
        guard let right = rhs.label else { return true }
        return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
      }
      .map { LabelTotal(label: $0.label, pomodoros: $0.pomodoros, focusSeconds: $0.seconds) }
  }

  /// What the Statistics list shows: the `limit` longest named labels, the rest of
  /// the named ones together as "Other", and the time without a label.
  struct LabelBreakdown: Equatable {
    let top: [LabelTotal]
    let otherSeconds: TimeInterval
    let unlabeledSeconds: TimeInterval

    var otherMinutes: Int { Int((otherSeconds / 60).rounded()) }
    var unlabeledMinutes: Int { Int((unlabeledSeconds / 60).rounded()) }
  }

  static func labelBreakdown(_ totals: [LabelTotal], limit: Int = 5) -> LabelBreakdown {
    let named = totals.filter { $0.label != nil }
    return LabelBreakdown(
      top: Array(named.prefix(limit)),
      otherSeconds: named.dropFirst(limit).reduce(0) { $0 + $1.focusSeconds },
      unlabeledSeconds: totals.first { $0.label == nil }?.focusSeconds ?? 0)
  }

  /// How many of `days` met a daily goal (0 with no goal).
  static func daysReachingGoal(_ days: [Day], goal: Int) -> Int {
    days.filter { DailyGoal.isReached(completed: $0.pomodoros, goal: goal) }.count
  }

  /// Consecutive days that met `goal`, counted back from the last of `days`
  /// (oldest first, today last). A today that hasn't met the goal yet doesn't break
  /// the streak, it just isn't part of it. 0 with no goal. The same goal applies to
  /// every day, since the goal isn't stored per day.
  static func goalStreak(days: [Day], goal: Int) -> Int {
    guard goal > DailyGoal.off else { return 0 }
    var streak = 0
    for (offset, day) in days.reversed().enumerated() {
      if DailyGoal.isReached(completed: day.pomodoros, goal: goal) {
        streak += 1
      } else if offset > 0 {
        break
      }
    }
    return streak
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

  /// Focus time per label over the last `days` days.
  func labelTotals(days: Int) -> [SessionStatistics.LabelTotal] {
    SessionStatistics.labelTotals(
      from: records, today: currentDate, length: days, calendar: calendar)
  }

  /// Consecutive days up to today that met `goal`, from the kept history.
  func goalStreak(goal: Int) -> Int {
    SessionStatistics.goalStreak(
      days: SessionStatistics.days(
        from: records, endingOn: currentDate, count: Self.retentionDays, calendar: calendar),
      goal: goal)
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

  /// One row per completed session kept in the history, oldest first:
  /// `start,end,kind,minutes,label`. Times are ISO 8601 in the history calendar's time
  /// zone, `kind` is `focus`, `short_break` or `long_break`, `minutes` is rounded. Fields are
  /// quoted as RFC 4180 asks and lines end in CRLF. A label that would be read as a formula
  /// by a spreadsheet (starting with `=`, `+`, `-`, `@`, tab or CR) gets a leading `'`.
  func sessionsCSV() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = calendar.timeZone
    formatter.formatOptions = [.withInternetDateTime]
    var lines = ["start,end,kind,minutes,label"]
    for record in records.filter(\.completed).sorted(by: { $0.start < $1.start }) {
      let kind: String
      switch record.kind {
      case .focus: kind = "focus"
      case .short: kind = "short_break"
      case .long: kind = "long_break"
      }
      let minutes = Int((record.duration / 60).rounded())
      lines.append(
        [
          formatter.string(from: record.start), formatter.string(from: record.end), kind,
          String(minutes), Self.csvField(label: record.label),
        ].joined(separator: ","))
    }
    return lines.joined(separator: "\r\n") + "\r\n"
  }

  static func csvField(label: String?) -> String {
    guard var text = label, !text.isEmpty else { return "" }
    // Compared by unicode scalar: "\r\n" is one Character in Swift.
    let formulaStarts = "=+-@\t\r".unicodeScalars
    let needsQuotes = ",\"\r\n".unicodeScalars
    if let first = text.unicodeScalars.first, formulaStarts.contains(first) { text = "'" + text }
    guard text.unicodeScalars.contains(where: needsQuotes.contains) else { return text }
    return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }
}
