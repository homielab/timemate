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
    /// Start of the day of the oldest record; nil without records.
    var firstDay: Date? = nil

    var length: Int { days.count }
    /// Days of the period from the first day with data, so a new user's average
    /// isn't diluted by the days before they started.
    var activeDays: [Day] {
      guard let firstDay else { return days }
      return days.filter { $0.date >= firstDay }
    }
    /// Minutes per day since the first day with data; nil when the period is empty.
    var dailyAverage: Int? { SessionStatistics.dailyAverage(activeDays) }
    /// The previous period is only comparable when the history covers all of it.
    var hasFullPreviousPeriod: Bool {
      guard let firstDay, let start = previousDays.first?.date else { return false }
      return firstDay <= start
    }
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
    return Period(
      days: Array(both.suffix(length)), previousDays: Array(both.prefix(length)),
      firstDay: firstDay(of: records, calendar: calendar))
  }

  /// Start of the day of the oldest record, or nil without records.
  static func firstDay(of records: [SessionHistory.Record], calendar: Calendar) -> Date? {
    records.map(\.end).min().map { calendar.startOfDay(for: $0) }
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

  /// Focus seconds per hour of the day (24 entries, index = local hour) over the last
  /// `length` days (the window of `period`, by session end). Each completed focus
  /// session runs from `end - duration` to `end` and is split across the hours it
  /// touches, so 9:50–10:15 adds 10 minutes to hour 9 and 15 to hour 10. The repeated
  /// hour of a DST fall-back counts into that hour; a skipped hour stays empty.
  static func hourlyFocus(
    from records: [SessionHistory.Record], today: Date, length: Int, calendar: Calendar
  ) -> [TimeInterval] {
    var hours = [TimeInterval](repeating: 0, count: 24)
    let lastDay = calendar.startOfDay(for: today)
    guard
      let firstDay = calendar.date(byAdding: .day, value: -(max(1, length) - 1), to: lastDay),
      let end = calendar.date(byAdding: .day, value: 1, to: lastDay)
    else { return hours }
    let start = calendar.startOfDay(for: firstDay)
    for record in records
    where record.kind == .focus && record.completed && record.end >= start && record.end < end {
      var cursor = record.end.addingTimeInterval(-record.duration)
      while cursor < record.end {
        let hourEnd = calendar.dateInterval(of: .hour, for: cursor)?.end ?? record.end
        let chunkEnd = min(max(hourEnd, cursor.addingTimeInterval(1)), record.end)
        hours[calendar.component(.hour, from: cursor)] += chunkEnd.timeIntervalSince(cursor)
        cursor = chunkEnd
      }
    }
    return hours
  }

  /// The hour (0–23) with the most focus time; on a tie the earliest. Nil when empty.
  static func mostFocusedHour(_ hours: [TimeInterval]) -> Int? {
    guard let best = hours.max(), best > 0 else { return nil }
    return hours.firstIndex(of: best)
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

  /// Width of a "By label" bar: `seconds` against the longest, kept within 0…1 so the
  /// "Other" bar (several labels together) never runs past its row.
  static func barFraction(_ seconds: TimeInterval, longest: TimeInterval) -> Double {
    guard longest > 0 else { return 0 }
    return min(1, max(0, seconds / longest))
  }

  static func labelBreakdown(_ totals: [LabelTotal], limit: Int = 5) -> LabelBreakdown {
    let named = totals.filter { $0.label != nil }
    return LabelBreakdown(
      top: Array(named.prefix(limit)),
      otherSeconds: named.dropFirst(limit).reduce(0) { $0 + $1.focusSeconds },
      unlabeledSeconds: totals.first { $0.label == nil }?.focusSeconds ?? 0)
  }

  /// Focus minutes per day over `days`: the total minutes divided by the number of
  /// days (empty days count), rounded to a whole minute. Nil when the days hold no
  /// focus time, so an empty period shows no average.
  static func dailyAverage(_ days: [Day]) -> Int? {
    let minutes = Totals(days).focusMinutes
    guard minutes > 0, !days.isEmpty else { return nil }
    return Int((Double(minutes) / Double(days.count)).rounded())
  }

  /// The day of `days` with the most pomodoros; on a tie the newest of them. Nil
  /// when no day has a pomodoro.
  static func bestDay(_ days: [Day]) -> Day? {
    days.filter { $0.pomodoros > 0 }.max { ($0.pomodoros, $0.date) < ($1.pomodoros, $1.date) }
  }

  /// How many of `days` met a daily goal (0 with no goal).
  static func daysReachingGoal(_ days: [Day], goal: Int) -> Int {
    days.filter { DailyGoal.isReached(completed: $0.pomodoros, goal: goal) }.count
  }

  /// Consecutive days that met `goal`, counted back from the last of `days`
  /// (oldest first, today last). A today that hasn't met the goal yet doesn't break
  /// the streak, it just isn't part of it. 0 with no goal. The same goal applies to
  /// every day, since the goal isn't stored per day. `carried` days (from before
  /// the first of `days`, see `GoalStreakCarry`) are added only when the streak
  /// reaches back over all of `days`. With `skipWeekends` a Saturday or Sunday that
  /// missed the goal neither breaks the streak nor counts; one that met it counts.
  static func goalStreak(
    days: [Day], goal: Int, carried: Int = 0, skipWeekends: Bool = false,
    calendar: Calendar = .current
  ) -> Int {
    guard goal > DailyGoal.off else { return 0 }
    var streak = 0
    for (offset, day) in days.reversed().enumerated() {
      if DailyGoal.isReached(completed: day.pomodoros, goal: goal) {
        streak += 1
      } else if offset > 0, !(skipWeekends && isWeekend(day.date, calendar: calendar)) {
        return streak
      }
    }
    return streak + max(0, carried)
  }

  /// Saturday or Sunday, whatever the system region calls the weekend (Fri–Sat in
  /// the UAE), so 'Weekends don't break the streak' does what its caption says.
  static func isWeekend(_ date: Date, calendar: Calendar) -> Bool {
    let weekday = calendar.component(.weekday, from: date)
    return weekday == 1 || weekday == 7
  }

  /// The longest run of consecutive `days` that met `goal`, anywhere in `days`
  /// (today included only once reached). 0 with no goal. `skipWeekends` as in
  /// `goalStreak`.
  static func longestStreak(
    days: [Day], goal: Int, skipWeekends: Bool = false, calendar: Calendar = .current
  ) -> Int {
    guard goal > DailyGoal.off else { return 0 }
    var best = 0
    var run = 0
    for day in days {
      if DailyGoal.isReached(completed: day.pomodoros, goal: goal) {
        run += 1
      } else if !(skipWeekends && isWeekend(day.date, calendar: calendar)) {
        run = 0
      }
      best = max(best, run)
    }
    return best
  }

  /// `date` as `yyyy-MM-dd` in the Gregorian calendar and `timeZone`, whatever
  /// calendar the user picked (Buddhist, Japanese…), so spreadsheets read it as a date.
  static func isoDay(_ date: Date, timeZone: TimeZone) -> String {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = timeZone
    let parts = gregorian.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  /// `date,pomodoros,minutes` with one row per day, dates as Gregorian `yyyy-MM-dd`
  /// in the calendar's time zone (days still split by `calendar`), lines ending in CRLF (RFC 4180). With a daily goal
  /// (`goal` > 0) a `goal_reached` column says 1 or 0 for each day.
  static func csv(for days: [Day], calendar: Calendar, goal: Int = DailyGoal.off) -> String {
    let withGoal = goal > DailyGoal.off
    var lines = [withGoal ? "date,pomodoros,minutes,goal_reached" : "date,pomodoros,minutes"]
    for day in days {
      let date = isoDay(day.date, timeZone: calendar.timeZone)
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

  /// Focus seconds per hour of the day over the last `days` days.
  func hourlyFocus(days: Int) -> [TimeInterval] {
    SessionStatistics.hourlyFocus(
      from: records, today: currentDate, length: days, calendar: calendar)
  }

  /// Consecutive days up to today that met `goal`: the kept history, plus the
  /// days carried from trimmed history when the streak runs back to them. With
  /// `skipWeekends` (weekends that missed the goal don't break the streak) the
  /// carry is ignored, because it was counted with every day able to break it;
  /// the streak then reaches back at most over the kept 90 days.
  func goalStreak(goal: Int, skipWeekends: Bool = false) -> Int {
    let today = calendar.startOfDay(for: currentDate)
    if !skipWeekends, let carry = goalStreakCarry, carry.throughDay < today,
      let span = calendar.dateComponents([.day], from: carry.throughDay, to: today).day, span > 0
    {
      return SessionStatistics.goalStreak(
        days: SessionStatistics.days(
          from: records, endingOn: currentDate, count: span, calendar: calendar),
        goal: goal, carried: carry.streak(goal: goal))
    }
    return SessionStatistics.goalStreak(
      days: SessionStatistics.days(
        from: records, endingOn: currentDate, count: Self.retentionDays, calendar: calendar),
      goal: goal, skipWeekends: skipWeekends, calendar: calendar)
  }

  /// The longest goal streak within the kept history (the last 90 days); trimmed
  /// days are not counted, since the carry keeps only the current streak.
  func longestGoalStreak(goal: Int, skipWeekends: Bool = false) -> Int {
    SessionStatistics.longestStreak(
      days: SessionStatistics.days(
        from: records, endingOn: currentDate, count: Self.retentionDays, calendar: calendar),
      goal: goal, skipWeekends: skipWeekends, calendar: calendar)
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
    if looksLikeFormula(text) { text = "'" + text }
    // Compared by unicode scalar: "\r\n" is one Character in Swift.
    let needsQuotes = ",\"\r\n".unicodeScalars
    guard text.unicodeScalars.contains(where: needsQuotes.contains) else { return text }
    return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }

  /// Whether a spreadsheet would read `text` as a formula: it starts with `=`, tab or
  /// CR, or with `+ - @` followed by something a formula needs (a digit, `(`, another
  /// sign, or a cell reference, function or DDE call such as `A1`, `SUM(`, `cmd|`, `Sheet!`). A plain number
  /// (`+5`, `-1.5`) and words (`@Acme`, `-research`) are left alone.
  static func looksLikeFormula(_ text: String) -> Bool {
    let scalars = Array(text.unicodeScalars)
    guard let first = scalars.first else { return false }
    if "=\t\r".unicodeScalars.contains(first) { return true }
    guard "+-@".unicodeScalars.contains(first) else { return false }
    let rest = String(String.UnicodeScalarView(scalars.dropFirst()))
    if rest.range(of: #"^[0-9]+([.,][0-9]+)?$"#, options: .regularExpression) != nil {
      return false
    }
    return rest.range(of: #"^([0-9(=+\-@]|[A-Za-z]+[0-9(|!])"#, options: .regularExpression)
      != nil
  }
}
