//  Created by homielab.com

import XCTest

@testable import TimeMate

final class SessionStatisticsTests: XCTestCase {
  private typealias Record = SessionHistory.Record

  private func calendar(_ timeZone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZone)!
    return calendar
  }

  /// A date from local wall-clock components in `calendar`'s time zone.
  private func date(
    _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
    in calendar: Calendar
  ) -> Date {
    calendar.date(
      from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  private func focus(end: Date, minutes: Double = 25) -> Record {
    Record(start: end.addingTimeInterval(-minutes * 60), end: end, kind: .focus, completed: true)
  }

  // MARK: - Grouping by day

  func testSevenDaysOldestFirstWithEmptyDaysAsZero() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)
    let records = [
      focus(end: date(2026, 3, 10, 9, in: utc)),
      focus(end: date(2026, 3, 10, 11, in: utc), minutes: 50),
      focus(end: date(2026, 3, 7, 8, in: utc)),
      Record(
        start: date(2026, 3, 7, 9, in: utc), end: date(2026, 3, 7, 9, 5, in: utc),
        kind: .short, completed: true),
      Record(
        start: date(2026, 3, 8, 9, in: utc), end: date(2026, 3, 8, 9, 25, in: utc),
        kind: .focus, completed: false),
    ]

    let days = SessionStatistics.days(from: records, endingOn: today, count: 7, calendar: utc)

    XCTAssertEqual(days.count, 7)
    XCTAssertEqual(days.first?.date, date(2026, 3, 4, in: utc))
    XCTAssertEqual(days.last?.date, date(2026, 3, 10, in: utc))
    XCTAssertEqual(days.map(\.pomodoros), [0, 0, 0, 1, 0, 0, 2])
    XCTAssertEqual(days.map(\.focusMinutes), [0, 0, 0, 25, 0, 0, 75])
  }

  func testSessionAcrossMidnightCountsOnTheDayItEnds() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 12, in: utc)
    // 23:50 → 00:15: belongs to the 10th, the day it was completed.
    let records = [
      focus(end: date(2026, 3, 10, 0, 15, in: utc)),
      focus(end: date(2026, 3, 9, 23, 59, in: utc)),
    ]

    let days = SessionStatistics.days(from: records, endingOn: today, count: 2, calendar: utc)

    XCTAssertEqual(days.map(\.pomodoros), [1, 1])
  }

  func testTimeZoneDecidesTheLocalDay() {
    // 2026-03-09 23:30 UTC is already 06:30 on the 10th in Ho Chi Minh City.
    let end = date(2026, 3, 9, 23, 30, in: calendar("UTC"))
    let records = [focus(end: end)]

    let utc = calendar("UTC")
    let utcDays = SessionStatistics.days(
      from: records, endingOn: date(2026, 3, 10, 12, in: utc), count: 2, calendar: utc)
    XCTAssertEqual(utcDays.map(\.pomodoros), [1, 0])

    let saigon = calendar("Asia/Ho_Chi_Minh")
    let saigonDays = SessionStatistics.days(
      from: records, endingOn: date(2026, 3, 10, 12, in: saigon), count: 2, calendar: saigon)
    XCTAssertEqual(saigonDays.map(\.pomodoros), [0, 1])
    XCTAssertEqual(saigonDays.last?.date, date(2026, 3, 10, in: saigon))
  }

  func testDaylightSavingDayIsStillOneDay() {
    // US clocks spring forward on 2026-03-08 (a 23-hour day).
    let newYork = calendar("America/New_York")
    let today = date(2026, 3, 9, 10, in: newYork)
    let records = [
      focus(end: date(2026, 3, 8, 1, 30, in: newYork)),
      focus(end: date(2026, 3, 8, 23, 30, in: newYork)),
      focus(end: date(2026, 3, 9, 0, 30, in: newYork)),
    ]

    let days = SessionStatistics.days(
      from: records, endingOn: today, count: 3, calendar: newYork)

    let expected = [7, 8, 9].map { date(2026, 3, $0, in: newYork) }
    XCTAssertEqual(days.map(\.date), expected)
    XCTAssertEqual(days.map(\.pomodoros), [0, 2, 1])
  }

  // MARK: - Week totals

  func testWeekTotalsAndPreviousWeek() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 14, 18, in: utc)
    let records = [
      focus(end: date(2026, 3, 14, 9, in: utc)),
      focus(end: date(2026, 3, 8, 9, in: utc), minutes: 30),  // first day of this week
      focus(end: date(2026, 3, 7, 9, in: utc)),  // last day of the previous week
      focus(end: date(2026, 3, 1, 9, in: utc)),  // first day of the previous week
      focus(end: date(2026, 2, 28, 9, in: utc)),  // too old for either
    ]

    let week = SessionStatistics.week(from: records, today: today, calendar: utc)

    XCTAssertEqual(week.days.count, 7)
    XCTAssertEqual(week.previousDays.count, 7)
    XCTAssertEqual(week.days.first?.date, date(2026, 3, 8, in: utc))
    XCTAssertEqual(week.totals, SessionStatistics.Totals(pomodoros: 2, focusMinutes: 55))
    XCTAssertEqual(week.previousTotals, SessionStatistics.Totals(pomodoros: 2, focusMinutes: 50))
  }

  // MARK: - 30-day period

  func testThirtyDayPeriodAndThePeriodBefore() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 31, 18, in: utc)
    let records = [
      focus(end: date(2026, 3, 31, 9, in: utc)),
      focus(end: date(2026, 3, 2, 9, in: utc), minutes: 30),  // first day of the period
      focus(end: date(2026, 3, 1, 9, in: utc)),  // last day of the previous period
      focus(end: date(2026, 1, 31, 9, in: utc)),  // first day of the previous period
      focus(end: date(2026, 1, 30, 9, in: utc)),  // too old
    ]

    let period = SessionStatistics.period(from: records, today: today, length: 30, calendar: utc)

    XCTAssertEqual(period.length, 30)
    XCTAssertEqual(period.previousDays.count, 30)
    XCTAssertEqual(period.days.first?.date, date(2026, 3, 2, in: utc))
    XCTAssertEqual(period.days.last?.date, date(2026, 3, 31, in: utc))
    XCTAssertEqual(period.previousDays.first?.date, date(2026, 1, 31, in: utc))
    XCTAssertEqual(period.totals, SessionStatistics.Totals(pomodoros: 2, focusMinutes: 55))
    XCTAssertEqual(period.previousTotals, SessionStatistics.Totals(pomodoros: 2, focusMinutes: 50))
  }

  func testPeriodKeepsOneRowPerDayAcrossDaylightSaving() {
    let newYork = calendar("America/New_York")  // clocks went forward on 2026-03-08
    let today = date(2026, 3, 20, 12, in: newYork)
    let period = SessionStatistics.period(
      from: [focus(end: date(2026, 3, 8, 12, in: newYork))], today: today, length: 30,
      calendar: newYork)

    XCTAssertEqual(period.days.count, 30)
    XCTAssertEqual(Set(period.days.map(\.date)).count, 30)
    XCTAssertEqual(period.days.first?.date, date(2026, 2, 19, in: newYork))
    XCTAssertEqual(
      period.days.first(where: { $0.pomodoros == 1 })?.date, date(2026, 3, 8, in: newYork))
    XCTAssertEqual(period.previousDays.last?.date, date(2026, 2, 18, in: newYork))
  }

  func testPercentChange() {
    XCTAssertEqual(SessionStatistics.percentChange(current: 15, previous: 10), 50)
    XCTAssertEqual(SessionStatistics.percentChange(current: 9, previous: 10), -10)
    XCTAssertEqual(SessionStatistics.percentChange(current: 10, previous: 10), 0)
    XCTAssertEqual(SessionStatistics.percentChange(current: 0, previous: 4), -100)
    XCTAssertEqual(SessionStatistics.percentChange(current: 1, previous: 3), -67)
    XCTAssertEqual(SessionStatistics.percentChange(current: 2, previous: 3), -33)
    // Nothing to compare with: no percentage at all.
    XCTAssertNil(SessionStatistics.percentChange(current: 5, previous: 0))
    XCTAssertNil(SessionStatistics.percentChange(current: 0, previous: 0))
  }

  func testStoredPeriodLengthFallsBackToAWeek() {
    XCTAssertEqual(SessionStatistics.sanitizedLength(7), 7)
    XCTAssertEqual(SessionStatistics.sanitizedLength(30), 30)
    XCTAssertEqual(SessionStatistics.sanitizedLength(14), 7)
    XCTAssertEqual(SessionStatistics.sanitizedLength(0), 7)
    XCTAssertEqual(SessionStatistics.sanitizedLength(nil), 7)
  }

  func testHistoryStatisticsAndCSVFollowTheChosenPeriod() {
    let utc = calendar("UTC")
    let now = date(2026, 3, 31, 15, in: utc)
    let history = SessionHistory(fileURL: nil, now: { now }, calendar: utc)
    history.recordCompletedSession(.focus, duration: 1500, end: date(2026, 3, 31, 9, in: utc))
    history.recordCompletedSession(.focus, duration: 1500, end: date(2026, 3, 5, 9, in: utc))

    XCTAssertEqual(history.statistics(days: 7).totals.pomodoros, 1)
    XCTAssertEqual(history.statistics(days: 30).totals.pomodoros, 2)

    let lines = history.statisticsCSV(days: 30, goal: 1).components(separatedBy: "\r\n")
    XCTAssertEqual(lines.first, "date,pomodoros,minutes,goal_reached")
    XCTAssertEqual(lines.count, 1 + 30 + 1)  // header + 30 rows + ""
    XCTAssertEqual(lines[1], "2026-03-02,0,0,0")
    XCTAssertEqual(lines[lines.count - 2], "2026-03-31,1,25,1")
    XCTAssertEqual(history.statisticsCSV(days: 7).components(separatedBy: "\r\n").count, 1 + 7 + 1)
  }

  func testTotalMinutesAddUpTheRoundedDays() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 18, in: utc)
    // 20.4 min on two days: each row shows 20, so the total shows 40 (not 41).
    let records = [
      focus(end: date(2026, 3, 9, 9, in: utc), minutes: 20.4),
      focus(end: date(2026, 3, 10, 9, in: utc), minutes: 20.4),
    ]

    let week = SessionStatistics.week(from: records, today: today, calendar: utc)

    XCTAssertEqual(week.totals.focusMinutes, 40)
  }

  func testSignedChange() {
    XCTAssertEqual(SessionStatistics.signedChange(3), "+3")
    XCTAssertEqual(SessionStatistics.signedChange(-20), "\u{2212}20")
    XCTAssertEqual(SessionStatistics.signedChange(0), "0")
  }

  // MARK: - CSV

  func testCSVHasHeaderAndOneRowPerDay() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)
    let records = [
      focus(end: date(2026, 3, 10, 9, in: utc)),
      focus(end: date(2026, 3, 10, 10, in: utc), minutes: 50),
    ]
    let days = SessionStatistics.days(from: records, endingOn: today, count: 3, calendar: utc)

    let csv = SessionStatistics.csv(for: days, calendar: utc)

    XCTAssertEqual(
      csv,
      "date,pomodoros,minutes\r\n2026-03-08,0,0\r\n2026-03-09,0,0\r\n2026-03-10,2,75\r\n")
  }

  func testCSVAddsGoalReachedColumnOnlyWithAGoal() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)
    let records = [
      focus(end: date(2026, 3, 9, 9, in: utc)),
      focus(end: date(2026, 3, 10, 9, in: utc)),
      focus(end: date(2026, 3, 10, 10, in: utc)),
    ]
    let days = SessionStatistics.days(from: records, endingOn: today, count: 3, calendar: utc)

    XCTAssertEqual(
      SessionStatistics.csv(for: days, calendar: utc, goal: 2),
      "date,pomodoros,minutes,goal_reached\r\n2026-03-08,0,0,0\r\n2026-03-09,1,25,0\r\n"
        + "2026-03-10,2,50,1\r\n")
    XCTAssertEqual(
      SessionStatistics.csv(for: days, calendar: utc, goal: 0),
      SessionStatistics.csv(for: days, calendar: utc))
    XCTAssertTrue(
      SessionStatistics.csv(for: days, calendar: utc).hasPrefix("date,pomodoros,minutes\r\n"))
  }

  func testDaysReachingGoal() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)
    let records = [
      focus(end: date(2026, 3, 8, 9, in: utc)),
      focus(end: date(2026, 3, 9, 9, in: utc)),
      focus(end: date(2026, 3, 9, 10, in: utc)),
      focus(end: date(2026, 3, 10, 9, in: utc)),
      focus(end: date(2026, 3, 10, 10, in: utc)),
      focus(end: date(2026, 3, 10, 11, in: utc)),
    ]
    let week = SessionStatistics.week(from: records, today: today, calendar: utc)

    XCTAssertEqual(SessionStatistics.daysReachingGoal(week.days, goal: 1), 3)
    XCTAssertEqual(SessionStatistics.daysReachingGoal(week.days, goal: 2), 2)
    XCTAssertEqual(SessionStatistics.daysReachingGoal(week.days, goal: 4), 0)
    XCTAssertEqual(SessionStatistics.daysReachingGoal(week.days, goal: 0), 0)
  }

  func testCSVDatesUseTheLocalDay() {
    let saigon = calendar("Asia/Ho_Chi_Minh")
    let days = SessionStatistics.days(
      from: [focus(end: date(2026, 1, 1, 0, 30, in: saigon))],
      endingOn: date(2026, 1, 1, 8, in: saigon), count: 1, calendar: saigon)

    XCTAssertEqual(
      SessionStatistics.csv(for: days, calendar: saigon),
      "date,pomodoros,minutes\r\n2026-01-01,1,25\r\n")
  }

  func testExportCoversAtLeastTheRetentionWindowAndEveryRecord() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)

    let empty = SessionStatistics.allDays(
      from: [], today: today, minimumDays: 90, calendar: utc)
    XCTAssertEqual(empty.count, 90)
    XCTAssertEqual(empty.last?.date, date(2026, 3, 10, in: utc))

    // A record on day -90 (kept by the 90-day trim) still gets its row.
    let old = utc.date(byAdding: .day, value: -90, to: date(2026, 3, 10, 20, in: utc))!
    let withOld = SessionStatistics.allDays(
      from: [focus(end: old)], today: today, minimumDays: 90, calendar: utc)
    XCTAssertEqual(withOld.count, 91)
    XCTAssertEqual(withOld.first?.pomodoros, 1)
  }

  func testHistoryExportUsesItsClockAndCalendar() {
    let utc = calendar("UTC")
    let now = date(2026, 3, 10, 15, in: utc)
    let history = SessionHistory(fileURL: nil, now: { now }, calendar: utc)
    history.recordCompletedSession(.focus, duration: 1500, end: date(2026, 3, 10, 9, in: utc))

    let lines = history.statisticsCSV().components(separatedBy: "\r\n")
    XCTAssertEqual(lines.first, "date,pomodoros,minutes")
    XCTAssertEqual(lines.count, 1 + SessionHistory.retentionDays + 1)  // header + rows + ""
    XCTAssertEqual(lines[lines.count - 2], "2026-03-10,1,25")
    XCTAssertEqual(history.statistics(days: 7).totals.pomodoros, 1)
  }

  // MARK: - Labels

  func testDayLabelsFollowTheGivenLocale() {
    let utc = calendar("UTC")
    let monday = date(2026, 3, 9, in: utc)

    let english = StatisticsFormat.spokenDay(
      monday, calendar: utc, locale: Locale(identifier: "en"))
    XCTAssertTrue(english.contains("Monday"), english)
    XCTAssertTrue(english.contains("9"), english)

    let vietnamese = StatisticsFormat.spokenDay(
      monday, calendar: utc, locale: Locale(identifier: "vi"))
    XCTAssertTrue(vietnamese.lowercased().contains("thứ hai"), vietnamese)
  }

  func testShortDayLabelFollowsTheGivenLocale() {
    let utc = calendar("UTC")
    let monday = date(2026, 3, 9, in: utc)

    let english = StatisticsFormat.dayLabel(monday, calendar: utc, locale: Locale(identifier: "en"))
    XCTAssertTrue(english.contains("Mon"), english)
    XCTAssertTrue(english.contains("9"), english)

    let vietnamese = StatisticsFormat.dayLabel(
      monday, calendar: utc, locale: Locale(identifier: "vi"))
    XCTAssertTrue(vietnamese.contains("Thứ 2"), vietnamese)
    XCTAssertTrue(vietnamese.contains("9"), vietnamese)
  }

  func testDefaultFileName() {
    let utc = calendar("UTC")
    XCTAssertEqual(
      StatisticsExporter.defaultFileName(today: date(2026, 3, 10, 15, in: utc), calendar: utc),
      "TimeMate-statistics-2026-03-10.csv")
  }

  func testSessionsFileNameUsesTheLocalDayNearMidnight() {
    let utc = calendar("UTC")
    let hanoi = calendar("Asia/Ho_Chi_Minh")
    // 00:30 in Hà Nội on 21 Oct is still 17:30 UTC on 20 Oct.
    let justAfterMidnight = date(2026, 10, 21, 0, 30, in: hanoi)
    XCTAssertEqual(
      StatisticsExporter.sessionsFileName(today: justAfterMidnight, calendar: hanoi),
      "TimeMate-sessions-2026-10-21.csv")
    XCTAssertEqual(
      StatisticsExporter.sessionsFileName(today: justAfterMidnight, calendar: utc),
      "TimeMate-sessions-2026-10-20.csv")
  }

  func testExportDataStartsWithUTF8BOMAndKeepsTheTextVerbatim() {
    let csv = "start,label\r\n2026-03-10T08:00:00Z,Viết báo cáo\r\n"
    let data = StatisticsExporter.data(for: csv)
    XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
    XCTAssertEqual(String(decoding: data.dropFirst(3), as: UTF8.self), csv)
    XCTAssertEqual(Array(StatisticsExporter.data(for: "").prefix(3)), [0xEF, 0xBB, 0xBF])
  }

  // MARK: - Goal streak

  /// Days oldest first ending 2026-03-10, with the given pomodoro counts.
  private func streakDays(
    _ counts: [Int], endingOn end: (Int, Int, Int) = (2026, 3, 10),
    in calendar: Calendar
  ) -> [SessionStatistics.Day] {
    let today = date(end.0, end.1, end.2, 12, in: calendar)
    let records = counts.reversed().enumerated().flatMap { offset, count in
      (0..<count).map { _ in
        focus(end: calendar.date(byAdding: .day, value: -offset, to: today)!)
      }
    }
    return SessionStatistics.days(
      from: records, endingOn: today, count: counts.count, calendar: calendar)
  }

  func testStreakStartsFromYesterdayWhileTodayIsNotReached() {
    let utc = calendar("UTC")
    let days = streakDays([0, 4, 4, 1], in: utc)
    XCTAssertEqual(SessionStatistics.goalStreak(days: days, goal: 4), 2)
  }

  func testStreakIncludesTodayOnceReached() {
    let utc = calendar("UTC")
    let days = streakDays([0, 4, 4, 5], in: utc)
    XCTAssertEqual(SessionStatistics.goalStreak(days: days, goal: 4), 3)
  }

  func testAnEmptyDayBreaksTheStreak() {
    let utc = calendar("UTC")
    let days = streakDays([4, 4, 0, 4, 4], in: utc)
    XCTAssertEqual(SessionStatistics.goalStreak(days: days, goal: 4), 2)
    XCTAssertEqual(
      SessionStatistics.goalStreak(days: streakDays([4, 4, 3, 4], in: utc), goal: 4), 1)
  }

  func testNoGoalOrNoDaysMeansNoStreak() {
    let utc = calendar("UTC")
    XCTAssertEqual(SessionStatistics.goalStreak(days: streakDays([5, 5], in: utc), goal: 0), 0)
    XCTAssertEqual(SessionStatistics.goalStreak(days: [], goal: 3), 0)
    XCTAssertEqual(SessionStatistics.goalStreak(days: streakDays([0, 0], in: utc), goal: 3), 0)
  }

  func testStreakAcrossTheDaylightSavingChangeInNewYork() {
    let newYork = calendar("America/New_York")
    // 2026-11-01 has 25 hours; 2026-03-08 has 23.
    let fall = streakDays([2, 2, 2, 2, 0], endingOn: (2026, 11, 3), in: newYork)
    XCTAssertEqual(SessionStatistics.goalStreak(days: fall, goal: 2), 4)
    let spring = streakDays([2, 2, 2, 2], endingOn: (2026, 3, 10), in: newYork)
    XCTAssertEqual(SessionStatistics.goalStreak(days: spring, goal: 2), 4)
  }

  func testStreakAcrossTheNewYear() {
    let utc = calendar("UTC")
    let days = streakDays([1, 1, 1, 1, 1], endingOn: (2027, 1, 2), in: utc)
    XCTAssertEqual(SessionStatistics.goalStreak(days: days, goal: 1), 5)
    XCTAssertEqual(days.first?.date, date(2026, 12, 29, in: utc))
  }

  func testHistoryStreakIsCappedByTheKeptNinetyDays() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 12, in: utc)
    let history = SessionHistory(
      fileURL: nil, now: { today }, calendar: utc, notificationCenter: NotificationCenter())
    for offset in 0..<120 {
      history.recordCompletedSession(
        .focus, duration: 25 * 60, end: utc.date(byAdding: .day, value: -offset, to: today)!)
    }
    XCTAssertEqual(history.goalStreak(goal: 1), SessionHistory.retentionDays)
    XCTAssertEqual(history.goalStreak(goal: 2), 0)
  }

  // MARK: - Label totals

  private func labeled(_ label: String?, end: Date, minutes: Double = 25) -> Record {
    Record(
      start: end.addingTimeInterval(-minutes * 60), end: end, kind: .focus, completed: true,
      label: label)
  }

  func testLabelTotalsGroupIgnoringCaseKeepNewestSpellingAndGatherNoLabel() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)
    let records = [
      labeled("writing", end: date(2026, 3, 8, 9, in: utc), minutes: 25),
      labeled("Writing", end: date(2026, 3, 9, 9, in: utc), minutes: 50),
      labeled(nil, end: date(2026, 3, 9, 12, in: utc), minutes: 10),
      labeled("  ", end: date(2026, 3, 10, 9, in: utc), minutes: 5),
    ]

    let totals = SessionStatistics.labelTotals(
      from: records, today: today, length: 7, calendar: utc)

    XCTAssertEqual(totals.map(\.label), ["Writing", nil])
    XCTAssertEqual(totals[0].pomodoros, 2)
    XCTAssertEqual(totals[0].focusMinutes, 75)
    XCTAssertEqual(totals[1].pomodoros, 2)
    XCTAssertEqual(totals[1].focusMinutes, 15)
  }

  func testLabelTotalsWindowEdges() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)
    let records = [
      labeled("in", end: date(2026, 3, 4, 0, in: utc)),  // first moment of the 7 days
      labeled("old", end: date(2026, 3, 3, 23, 59, in: utc)),
      labeled("today", end: date(2026, 3, 10, 23, 59, in: utc)),
      labeled("future", end: date(2026, 3, 11, 0, in: utc)),
    ]

    let week = SessionStatistics.labelTotals(
      from: records, today: today, length: 7, calendar: utc)
    XCTAssertEqual(Set(week.compactMap(\.label)), ["in", "today"])

    let month = SessionStatistics.labelTotals(
      from: records, today: today, length: 30, calendar: utc)
    XCTAssertEqual(Set(month.compactMap(\.label)), ["in", "old", "today"])
  }

  func testLabelTotalsIgnoreBreaksAndUnfinishedSessions() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)
    let end = date(2026, 3, 10, 9, in: utc)
    let records = [
      Record(
        start: end.addingTimeInterval(-300), end: end, kind: .short, completed: true,
        label: "break"),
      Record(
        start: end.addingTimeInterval(-900), end: end, kind: .focus, completed: false,
        label: "stopped"),
      labeled("done", end: end),
    ]

    let totals = SessionStatistics.labelTotals(
      from: records, today: today, length: 7, calendar: utc)

    XCTAssertEqual(totals.map(\.label), ["done"])
    XCTAssertTrue(
      SessionStatistics.labelTotals(from: [], today: today, length: 7, calendar: utc).isEmpty)
  }

  func testLabelTotalsLongestFirstTiesByNameAndNoLabelLast() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)
    let end = date(2026, 3, 10, 9, in: utc)
    let records = [
      labeled(nil, end: end),
      labeled("beta", end: end),
      labeled("Alpha", end: end),
      labeled("long", end: end, minutes: 60),
    ]

    let totals = SessionStatistics.labelTotals(
      from: records, today: today, length: 7, calendar: utc)

    XCTAssertEqual(totals.map(\.label), ["long", "Alpha", "beta", nil])
  }

  func testLabelBreakdownTopFiveOtherAndNoLabel() {
    func total(_ label: String?, _ minutes: Double) -> SessionStatistics.LabelTotal {
      SessionStatistics.LabelTotal(label: label, pomodoros: 1, focusSeconds: minutes * 60)
    }
    let totals = [
      total("a", 70), total("b", 60), total(nil, 55), total("c", 50), total("d", 40),
      total("e", 30), total("f", 20), total("g", 10),
    ]

    let breakdown = SessionStatistics.labelBreakdown(totals)

    XCTAssertEqual(breakdown.top.map(\.label), ["a", "b", "c", "d", "e"])
    XCTAssertEqual(breakdown.otherMinutes, 30)
    XCTAssertEqual(breakdown.unlabeledMinutes, 55)
    XCTAssertEqual(SessionStatistics.labelBreakdown([]).otherSeconds, 0)
  }
}
