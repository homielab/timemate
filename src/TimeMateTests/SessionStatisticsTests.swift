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

  // MARK: - Daily average and best day

  private func day(_ date: Date, pomodoros: Int, minutes: Double) -> SessionStatistics.Day {
    SessionStatistics.Day(date: date, pomodoros: pomodoros, focusSeconds: minutes * 60)
  }

  func testDailyAverageCountsEmptyDaysAndRoundsToAMinute() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)
    let records = [
      focus(end: date(2026, 3, 8, 9, in: utc)),
      focus(end: date(2026, 3, 9, 9, in: utc)),
      focus(end: date(2026, 3, 10, 9, in: utc), minutes: 30),
    ]
    let week = SessionStatistics.week(from: records, today: today, calendar: utc)

    // 80 minutes over 7 days = 11.43 → 11.
    XCTAssertEqual(SessionStatistics.dailyAverage(week.days), 11)
    // 10.5 rounds up, 10.4 down.
    let start = date(2026, 3, 1, in: utc)
    XCTAssertEqual(
      SessionStatistics.dailyAverage([
        day(start, pomodoros: 1, minutes: 21), day(start + 86_400, pomodoros: 0, minutes: 0),
      ]), 11)
    let fiveDays = (0..<5).map {
      day(start + Double($0) * 86_400, pomodoros: $0 == 0 ? 2 : 0, minutes: $0 == 0 ? 52 : 0)
    }
    XCTAssertEqual(SessionStatistics.dailyAverage(fiveDays), 10)
  }

  func testDailyAverageIsHiddenForAnEmptyPeriod() {
    let utc = calendar("UTC")
    let week = SessionStatistics.week(
      from: [], today: date(2026, 3, 10, 15, in: utc), calendar: utc)
    XCTAssertNil(SessionStatistics.dailyAverage(week.days))
    XCTAssertNil(SessionStatistics.dailyAverage([]))
  }

  func testPeriodAverageStartsAtTheFirstDayWithData() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)
    // 4 days × 100 min in a 7-day window → 100, not 400 / 7.
    let fourDays = (0..<4).map { focus(end: date(2026, 3, 7 + $0, 9, in: utc), minutes: 100) }
    let week = SessionStatistics.week(from: fourDays, today: today, calendar: utc)
    XCTAssertEqual(week.firstDay, date(2026, 3, 7, in: utc))
    XCTAssertEqual(week.dailyAverage, 100)
    // First record today → today's minutes.
    let todayOnly = SessionStatistics.week(
      from: [focus(end: date(2026, 3, 10, 9, in: utc), minutes: 40)], today: today,
      calendar: utc)
    XCTAssertEqual(todayOnly.dailyAverage, 40)
    // No records → nothing.
    let empty = SessionStatistics.week(from: [], today: today, calendar: utc)
    XCTAssertNil(empty.firstDay)
    XCTAssertNil(empty.dailyAverage)
    XCTAssertFalse(empty.hasFullPreviousPeriod)
    // Data older than the window → every day of the window counts (80 / 7 = 11).
    let older = [
      focus(end: date(2026, 2, 1, 9, in: utc)), focus(end: date(2026, 3, 8, 9, in: utc)),
      focus(end: date(2026, 3, 9, 9, in: utc)),
      focus(end: date(2026, 3, 10, 9, in: utc), minutes: 30),
    ]
    XCTAssertEqual(
      SessionStatistics.week(from: older, today: today, calendar: utc).dailyAverage, 11)
  }

  func testComparisonNeedsTheWholePreviousPeriod() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 31, 15, in: utc)
    func days(_ count: Int) -> [Record] {
      (0..<count).map { focus(end: today - Double($0) * 86_400) }
    }
    // 30 days of data in a 30-day window → same as before: average over 30 days.
    let thirty = SessionStatistics.period(
      from: days(30), today: today, length: 30, calendar: utc)
    XCTAssertEqual(thirty.dailyAverage, 25)
    XCTAssertFalse(thirty.hasFullPreviousPeriod)
    // 40 days: the previous 30 only hold 10 real days → no comparison.
    let forty = SessionStatistics.period(
      from: days(40), today: today, length: 30, calendar: utc)
    XCTAssertFalse(forty.hasFullPreviousPeriod)
    // 60 days cover both periods.
    let sixty = SessionStatistics.period(
      from: days(60), today: today, length: 30, calendar: utc)
    XCTAssertTrue(sixty.hasFullPreviousPeriod)
  }

  func testBestDayHasTheMostPomodorosAndTheNewestOnATie() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)
    let records = [
      focus(end: date(2026, 3, 5, 9, in: utc)),
      focus(end: date(2026, 3, 5, 10, in: utc), minutes: 50),
      focus(end: date(2026, 3, 8, 9, in: utc)),
      focus(end: date(2026, 3, 8, 10, in: utc)),
      focus(end: date(2026, 3, 10, 9, in: utc)),
    ]
    let week = SessionStatistics.week(from: records, today: today, calendar: utc)

    let best = SessionStatistics.bestDay(week.days)
    XCTAssertEqual(best?.date, date(2026, 3, 8, in: utc))
    XCTAssertEqual(best?.pomodoros, 2)
    XCTAssertEqual(best?.focusMinutes, 50)
  }

  func testNoBestDayForAnEmptyPeriod() {
    let utc = calendar("UTC")
    let week = SessionStatistics.week(
      from: [], today: date(2026, 3, 10, 15, in: utc), calendar: utc)
    XCTAssertNil(SessionStatistics.bestDay(week.days))
    XCTAssertNil(SessionStatistics.bestDay([]))
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

  func testExportCoversAtLeastTheRetentionWindowAndEverySessionOfItsOldestDay() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)

    let empty = SessionStatistics.allDays(
      from: [], today: today, minimumDays: 90, calendar: utc)
    XCTAssertEqual(empty.count, 90)
    XCTAssertEqual(empty.last?.date, date(2026, 3, 10, in: utc))

    // The history keeps all of 2025-12-10, the day 90 days back, so the row for
    // that day counts both of its sessions instead of only the one after 15:00.
    let history = SessionHistory(fileURL: nil, now: { today }, calendar: utc)
    history.recordCompletedSession(.focus, duration: 1500, end: date(2025, 12, 10, 9, in: utc))
    history.recordCompletedSession(.focus, duration: 1500, end: date(2025, 12, 10, 20, in: utc))

    let lines = history.statisticsCSV().components(separatedBy: "\r\n")
    XCTAssertEqual(lines.first, "date,pomodoros,minutes")
    XCTAssertEqual(lines.count, 1 + 91 + 1)  // header + 90 days + the oldest day + ""
    XCTAssertEqual(lines[1], "2025-12-10,2,50")
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

  func testBarStripSpokenDaysNameEveryColumn() throws {
    let utc = calendar("UTC")
    let days = [
      SessionStatistics.Day(date: date(2026, 3, 8, in: utc), pomodoros: 0, focusSeconds: 0),
      SessionStatistics.Day(date: date(2026, 3, 9, in: utc), pomodoros: 4, focusSeconds: 6000),
    ]
    let path = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))
    let en = try XCTUnwrap(Bundle(path: path))
    let spoken = BarStrip.spokenDays(
      days, goal: 4, calendar: utc, locale: Locale(identifier: "en"), bundle: en)
    XCTAssertEqual(spoken.count, 2)
    XCTAssertTrue(spoken[0].contains("Sunday"), spoken[0])
    XCTAssertTrue(spoken[0].contains("0 pomodoros"), spoken[0])
    XCTAssertTrue(spoken[1].contains("Monday"), spoken[1])
    XCTAssertTrue(spoken[1].contains("4 pomodoros"), spoken[1])
    XCTAssertTrue(spoken[1].contains("100 minutes"), spoken[1])
    XCTAssertTrue(spoken[1].hasSuffix("goal reached"), spoken[1])
    XCTAssertFalse(spoken[0].contains("goal reached"), spoken[0])

    let viPath = try XCTUnwrap(Bundle.main.path(forResource: "vi", ofType: "lproj"))
    let vi = try XCTUnwrap(Bundle(path: viPath))
    let viSpoken = BarStrip.spokenDays(
      days, goal: 4, calendar: utc, locale: Locale(identifier: "vi_VN"), bundle: vi)
    XCTAssertEqual(viSpoken.count, 2)
    XCTAssertTrue(viSpoken[0].lowercased().contains("chủ nhật"), viSpoken[0])
    XCTAssertTrue(viSpoken[0].contains("0 pomodoro"), viSpoken[0])
    XCTAssertTrue(viSpoken[1].contains("4 pomodoro"), viSpoken[1])
    XCTAssertTrue(viSpoken[1].contains("100 phút"), viSpoken[1])
    XCTAssertTrue(viSpoken[1].hasSuffix("đạt mục tiêu"), viSpoken[1])
    XCTAssertFalse(viSpoken[0].contains("đạt mục tiêu"), viSpoken[0])
  }

  func testBarStripSpokenDaysSingularInEnglish() throws {
    let utc = calendar("UTC")
    let days = [
      SessionStatistics.Day(date: date(2026, 3, 9, in: utc), pomodoros: 1, focusSeconds: 60)
    ]
    let path = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))
    let en = try XCTUnwrap(Bundle(path: path))
    let spoken = BarStrip.spokenDays(
      days, goal: 0, calendar: utc, locale: Locale(identifier: "en_US"), bundle: en)
    XCTAssertTrue(spoken[0].hasSuffix("1 pomodoro, 1 minute"), spoken[0])
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

  func testDefaultFileNameNamesThePeriod() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)
    XCTAssertEqual(
      StatisticsExporter.defaultFileName(days: 7, today: today, calendar: utc),
      "TimeMate-statistics-7d-2026-03-10.csv")
    XCTAssertEqual(
      StatisticsExporter.defaultFileName(days: 30, today: today, calendar: utc),
      "TimeMate-statistics-30d-2026-03-10.csv")
    XCTAssertEqual(
      StatisticsExporter.defaultFileName(days: nil, today: today, calendar: utc),
      "TimeMate-statistics-all-2026-03-10.csv")
  }

  func testExportAllHasMoreRowsThanTheLongestPeriodWithALongHistory() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)
    let history = SessionHistory(fileURL: nil, now: { today }, calendar: utc)
    history.recordCompletedSession(.focus, duration: 1500, end: date(2026, 1, 20, 9, in: utc))
    history.recordCompletedSession(.focus, duration: 1500, end: date(2026, 3, 10, 9, in: utc))

    let month = history.statisticsCSV(days: SessionStatistics.monthLength, goal: 1)
      .components(separatedBy: "\r\n")
    let all = history.statisticsCSV(goal: 1).components(separatedBy: "\r\n")
    XCTAssertEqual(month.count, 1 + 30 + 1)
    XCTAssertGreaterThan(all.count - 2, 30)
    XCTAssertEqual(all.first, month.first)
    XCTAssertTrue(all.contains("2026-01-20,1,25,1"), "\(all.prefix(3))")
    XCTAssertFalse(month.contains("2026-01-20,1,25,1"))
  }

  func testCSVAndFileNamesUseGregorianYearsUnderOtherCalendars() {
    for identifier in [Calendar.Identifier.buddhist, .japanese] {
      var other = Calendar(identifier: identifier)
      other.timeZone = TimeZone(identifier: "Asia/Bangkok")!
      let gregorian = calendar("Asia/Bangkok")
      let today = date(2026, 10, 29, 15, in: gregorian)
      let records = [focus(end: date(2026, 10, 29, 9, in: gregorian))]
      let days = SessionStatistics.days(from: records, endingOn: today, count: 2, calendar: other)

      XCTAssertEqual(
        SessionStatistics.csv(for: days, calendar: other),
        "date,pomodoros,minutes\r\n2026-10-28,0,0\r\n2026-10-29,1,25\r\n", "\(identifier)")
      XCTAssertEqual(
        StatisticsExporter.defaultFileName(days: 7, today: today, calendar: other),
        "TimeMate-statistics-7d-2026-10-29.csv", "\(identifier)")
      XCTAssertEqual(
        StatisticsExporter.sessionsFileName(today: today, calendar: other),
        "TimeMate-sessions-2026-10-29.csv", "\(identifier)")
    }
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

  func testLongestStreakFindsTheRecordRun() {
    let utc = calendar("UTC")
    let twelveThenTwo = streakDays(Array(repeating: 4, count: 12) + [0, 4, 4], in: utc)
    XCTAssertEqual(SessionStatistics.longestStreak(days: twelveThenTwo, goal: 4), 12)
    XCTAssertEqual(SessionStatistics.goalStreak(days: twelveThenTwo, goal: 4), 2)
    XCTAssertEqual(SessionStatistics.longestStreak(days: twelveThenTwo, goal: 0), 0)
    XCTAssertEqual(
      SessionStatistics.longestStreak(days: streakDays([5, 5, 5], in: utc), goal: 4), 3)
    XCTAssertEqual(
      SessionStatistics.longestStreak(days: streakDays([1, 0, 3], in: utc), goal: 4), 0)
    XCTAssertEqual(SessionStatistics.longestStreak(days: [], goal: 4), 0)
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

  func testHistoryKeepsNinetyDaysWhenOlderSessionsAreAddedLater() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 12, in: utc)
    let history = SessionHistory(
      fileURL: nil, now: { today }, calendar: utc, notificationCenter: NotificationCenter())
    for offset in 0..<120 {
      history.recordCompletedSession(
        .focus, duration: 25 * 60, end: utc.date(byAdding: .day, value: -offset, to: today)!)
    }
    // Sessions older than the kept days are dropped as they come in.
    XCTAssertEqual(history.goalStreak(goal: 1), SessionHistory.retentionDays)
    XCTAssertEqual(history.goalStreak(goal: 2), 0)
  }

  /// Uses the app for `counts.count` days in a row (one entry per day, oldest
  /// first, the last one today), recording each day's pomodoros at noon.
  private func useDaily(_ counts: [Int], calendar: Calendar) -> SessionHistory {
    let first = date(2026, 1, 1, 12, in: calendar)
    var now = first
    let history = SessionHistory(
      fileURL: nil, now: { now }, calendar: calendar, notificationCenter: NotificationCenter())
    for (offset, count) in counts.enumerated() {
      now = calendar.date(byAdding: .day, value: offset, to: first)!
      for _ in 0..<count {
        history.recordCompletedSession(.focus, duration: 25 * 60, end: now)
      }
    }
    return history
  }

  func testStreakLongerThanTheKeptDaysCountsTheTrimmedDays() {
    let history = useDaily(Array(repeating: 1, count: 100), calendar: calendar("UTC"))
    XCTAssertLessThan(history.records.count, 100)
    XCTAssertEqual(history.goalStreak(goal: 1), 100)
    XCTAssertEqual(history.goalStreak(goal: 2), 0)
  }

  func testAMissedTrimmedDayCountsOnlyTheDaysAfterIt() {
    var counts = Array(repeating: 2, count: 100)
    counts[3] = 0
    counts[6] = 1
    let history = useDaily(counts, calendar: calendar("UTC"))
    XCTAssertEqual(history.goalStreak(goal: 1), 96)
    XCTAssertEqual(history.goalStreak(goal: 2), 93)
  }

  func testChangingTheGoalDropsCarriedDaysThatMissTheNewGoal() {
    // The first 10 days had one pomodoro, the next 90 two.
    let counts = Array(repeating: 1, count: 10) + Array(repeating: 2, count: 90)
    let history = useDaily(counts, calendar: calendar("UTC"))
    XCTAssertEqual(history.goalStreak(goal: 1), 100)
    XCTAssertEqual(history.goalStreak(goal: 2), 90)
    XCTAssertEqual(history.goalStreak(goal: 3), 0)
  }

  func testCarriedDaysCountOnlyWhileTheStreakReachesThem() {
    var counts = Array(repeating: 1, count: 100)
    counts[95] = 0
    let history = useDaily(counts, calendar: calendar("UTC"))
    XCTAssertEqual(history.goalStreak(goal: 1), 4)
  }

  func testTodayNotDoneYetStillCarriesTheTrimmedDays() {
    let history = useDaily(Array(repeating: 1, count: 100) + [0], calendar: calendar("UTC"))
    XCTAssertEqual(history.goalStreak(goal: 1), 100)
  }

  func testCarryAcrossTheDaylightSavingChangeInNewYork() {
    // 2026-03-08 (23 hours) is among the trimmed days.
    let history = useDaily(Array(repeating: 1, count: 160), calendar: calendar("America/New_York"))
    XCTAssertEqual(history.goalStreak(goal: 1), 160)
  }

  func testCarryStreakIsZeroOutsideTheGoalRange() {
    let carry = GoalStreakCarry(throughDay: Date(), streaks: [5, 3])
    XCTAssertEqual(carry.streak(goal: 1), 5)
    XCTAssertEqual(carry.streak(goal: 2), 3)
    XCTAssertEqual(carry.streak(goal: 3), 0)
    XCTAssertEqual(carry.streak(goal: 0), 0)
    XCTAssertEqual(carry.streak(goal: 25), 0)
  }

  func testCarryIsAddedOnlyWhenTheStreakCoversEveryDay() {
    let utc = calendar("UTC")
    XCTAssertEqual(
      SessionStatistics.goalStreak(days: streakDays([1, 1, 1], in: utc), goal: 1, carried: 7), 10)
    XCTAssertEqual(
      SessionStatistics.goalStreak(days: streakDays([1, 1, 0], in: utc), goal: 1, carried: 7), 9)
    XCTAssertEqual(
      SessionStatistics.goalStreak(days: streakDays([0, 1, 1], in: utc), goal: 1, carried: 7), 2)
    XCTAssertEqual(
      SessionStatistics.goalStreak(days: streakDays([1, 1], in: utc), goal: 0, carried: 7), 0)
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

  func testHourlyFocusSplitsSessionsAcrossHours() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)
    let records = [
      labeled(nil, end: date(2026, 3, 10, 10, 15, in: utc)),  // 9:50–10:15
      labeled(nil, end: date(2026, 3, 9, 14, 30, in: utc), minutes: 90),  // 13:00–14:30
      labeled(nil, end: date(2026, 3, 1, 9, in: utc)),  // outside the 7 days
    ]

    let hours = SessionStatistics.hourlyFocus(
      from: records, today: today, length: 7, calendar: utc)

    XCTAssertEqual(hours.count, 24)
    XCTAssertEqual(hours[9], 600)
    XCTAssertEqual(hours[10], 900)
    XCTAssertEqual(hours[13], 3600)
    XCTAssertEqual(hours[14], 1800)
    XCTAssertEqual(hours.reduce(0, +), (25 + 90) * 60)
    XCTAssertEqual(SessionStatistics.mostFocusedHour(hours), 13)
  }

  func testHourlyFocusIgnoresBreaksAndEmptyHistory() {
    let utc = calendar("UTC")
    let today = date(2026, 3, 10, 15, in: utc)
    let end = date(2026, 3, 10, 9, in: utc)
    let records = [
      Record(start: end.addingTimeInterval(-300), end: end, kind: .short, completed: true),
      Record(start: end.addingTimeInterval(-900), end: end, kind: .focus, completed: false),
    ]
    for history in [[], records] {
      let hours = SessionStatistics.hourlyFocus(
        from: history, today: today, length: 30, calendar: utc)
      XCTAssertEqual(hours, Array(repeating: 0, count: 24))
      XCTAssertNil(SessionStatistics.mostFocusedHour(hours))
    }
  }

  func testHourlyFocusAcrossDaylightSavingChanges() {
    let newYork = calendar("America/New_York")
    // 2026-03-08: 2:00 jumps to 3:00. 1:50–3:15 local is 25 real minutes.
    let spring = labeled(nil, end: date(2026, 3, 8, 3, 15, in: newYork))
    // 2026-11-01: 1:00–2:00 happens twice. A session over both 1 AMs counts into hour 1.
    let fallEnd = date(2026, 11, 1, 1, 30, in: newYork).addingTimeInterval(3600)
    let fall = Record(
      start: fallEnd.addingTimeInterval(-3600), end: fallEnd, kind: .focus, completed: true)

    let springHours = SessionStatistics.hourlyFocus(
      from: [spring], today: date(2026, 3, 8, 12, in: newYork), length: 7, calendar: newYork)
    XCTAssertEqual(springHours[1], 600)
    XCTAssertEqual(springHours[2], 0)
    XCTAssertEqual(springHours[3], 900)

    let fallHours = SessionStatistics.hourlyFocus(
      from: [fall], today: date(2026, 11, 1, 12, in: newYork), length: 7, calendar: newYork)
    XCTAssertEqual(fallHours[1], 3600)
    XCTAssertEqual(fallHours.reduce(0, +), 3600)
  }

  func testMostFocusedHourPicksEarliestOnTie() {
    var hours = [TimeInterval](repeating: 0, count: 24)
    hours[15] = 600
    hours[9] = 600
    XCTAssertEqual(SessionStatistics.mostFocusedHour(hours), 9)
  }

  // MARK: Weekends that don't break the streak

  /// Goal streak days from Monday 2026-10-26, one count per day, ending on `end`.
  private func weekDays(_ counts: [Int], endingOn end: (Int, Int, Int)) -> (
    [SessionStatistics.Day], Calendar
  ) {
    let utc = calendar("UTC")
    return (streakDays(counts, endingOn: end, in: utc), utc)
  }

  func testWeekendWithoutPomodorosKeepsTheStreakWhenSkipped() {
    // Mon–Fri reached, Sat/Sun empty, Monday reached.
    let (days, utc) = weekDays([4, 4, 4, 4, 4, 0, 0, 4], endingOn: (2026, 11, 2))
    XCTAssertEqual(
      SessionStatistics.goalStreak(days: days, goal: 4, skipWeekends: true, calendar: utc), 6)
    XCTAssertEqual(
      SessionStatistics.goalStreak(days: days, goal: 4, skipWeekends: false, calendar: utc), 1)
    XCTAssertEqual(
      SessionStatistics.longestStreak(days: days, goal: 4, skipWeekends: true, calendar: utc), 6)
    XCTAssertEqual(
      SessionStatistics.longestStreak(days: days, goal: 4, skipWeekends: false, calendar: utc), 5)
  }

  func testMissedWeekdayStillBreaksTheStreakWhenWeekendsAreSkipped() {
    let (days, utc) = weekDays([4, 4, 4, 0, 4, 0, 0, 4], endingOn: (2026, 11, 2))
    XCTAssertEqual(
      SessionStatistics.goalStreak(days: days, goal: 4, skipWeekends: true, calendar: utc), 2)
    XCTAssertEqual(
      SessionStatistics.longestStreak(days: days, goal: 4, skipWeekends: true, calendar: utc), 3)
  }

  func testEmptyWeekendTodayDoesNotBreakTheStreak() {
    // Today is Sunday 2026-11-01 with no pomodoros; Saturday is empty too.
    let (days, utc) = weekDays([4, 4, 4, 4, 4, 0, 0], endingOn: (2026, 11, 1))
    XCTAssertEqual(
      SessionStatistics.goalStreak(days: days, goal: 4, skipWeekends: true, calendar: utc), 5)
    XCTAssertEqual(
      SessionStatistics.goalStreak(days: days, goal: 4, skipWeekends: false, calendar: utc), 0)
  }

  func testWeekendThatMetTheGoalCounts() {
    let (days, utc) = weekDays([4, 4, 4, 4, 4, 4, 0, 4], endingOn: (2026, 11, 2))
    XCTAssertEqual(
      SessionStatistics.goalStreak(days: days, goal: 4, skipWeekends: true, calendar: utc), 7)
    XCTAssertEqual(
      SessionStatistics.longestStreak(days: days, goal: 4, skipWeekends: true, calendar: utc), 7)
  }
}
