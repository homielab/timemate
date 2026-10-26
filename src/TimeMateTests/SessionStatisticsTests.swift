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
    XCTAssertEqual(history.weekStatistics().totals.pomodoros, 1)
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

  func testDefaultFileName() {
    let utc = calendar("UTC")
    XCTAssertEqual(
      StatisticsExporter.defaultFileName(today: date(2026, 3, 10, 15, in: utc), calendar: utc),
      "TimeMate-statistics-2026-03-10.csv")
  }
}
