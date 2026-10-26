//  Created by homielab.com

import XCTest

@testable import TimeMate

/// Singular and plural forms of the statistics texts (Localizable.stringsdict).
final class StatisticsTextTests: XCTestCase {
  private func bundle(_ localization: String) throws -> Bundle {
    let path = try XCTUnwrap(
      Bundle(for: PomodoroTimer.self).path(forResource: localization, ofType: "lproj"))
    return try XCTUnwrap(Bundle(path: path))
  }

  func testEnglishTodayUsesSingularForOnePomodoro() throws {
    let en = try bundle("en")
    XCTAssertEqual(
      StatisticsText.today(pomodoros: 0, minutes: 0, bundle: en), "Today: 0 pomodoros · 0 min")
    XCTAssertEqual(
      StatisticsText.today(pomodoros: 1, minutes: 25, bundle: en), "Today: 1 pomodoro · 25 min")
    XCTAssertEqual(
      StatisticsText.today(pomodoros: 2, minutes: 50, bundle: en), "Today: 2 pomodoros · 50 min")
  }

  func testEnglishWeekAndChange() throws {
    let en = try bundle("en")
    XCTAssertEqual(
      StatisticsText.week(pomodoros: 1, minutes: 25, bundle: en), "Week: 1 pomodoro · 25 min")
    XCTAssertEqual(
      StatisticsText.week(pomodoros: 12, minutes: 300, bundle: en), "Week: 12 pomodoros · 300 min")
    XCTAssertEqual(
      StatisticsText.change(pomodoros: 1, percent: 50, minutes: 25, days: 7, bundle: en),
      "+1 pomodoro (+50%), +25 min vs the previous 7 days")
    XCTAssertEqual(
      StatisticsText.change(pomodoros: -1, percent: -100, minutes: -25, days: 7, bundle: en),
      "\u{2212}1 pomodoro (\u{2212}100%), \u{2212}25 min vs the previous 7 days")
    XCTAssertEqual(
      StatisticsText.change(pomodoros: -3, percent: -10, minutes: 0, days: 30, bundle: en),
      "\u{2212}3 pomodoros (\u{2212}10%), 0 min vs the previous 30 days")
    XCTAssertEqual(
      StatisticsText.change(pomodoros: 0, percent: 0, minutes: 0, days: 30, bundle: en),
      "0 pomodoros (0%), 0 min vs the previous 30 days")
  }

  func testEnglishMonthTotal() throws {
    let en = try bundle("en")
    XCTAssertEqual(
      StatisticsText.total(pomodoros: 40, minutes: 1000, days: 30, bundle: en),
      "Month: 40 pomodoros · \(NumberFormatter.localizedString(from: 1000, number: .decimal)) min")
    XCTAssertEqual(
      StatisticsText.total(pomodoros: 1, minutes: 25, days: 30, bundle: en),
      "Month: 1 pomodoro · 25 min")
    XCTAssertEqual(
      StatisticsText.total(pomodoros: 2, minutes: 50, days: 7, bundle: en),
      "Week: 2 pomodoros · 50 min")
  }

  func testEnglishSpokenDay() throws {
    let en = try bundle("en")
    XCTAssertEqual(
      StatisticsText.spokenDay("Monday, October 20", pomodoros: 1, minutes: 1, bundle: en),
      "Monday, October 20: 1 pomodoro, 1 minute")
    XCTAssertEqual(
      StatisticsText.spokenDay("Monday, October 20", pomodoros: 2, minutes: 50, bundle: en),
      "Monday, October 20: 2 pomodoros, 50 minutes")
  }

  func testEnglishDailyGoalTexts() throws {
    let en = try bundle("en")
    XCTAssertEqual(
      StatisticsText.today(pomodoros: 3, goal: 8, minutes: 75, bundle: en),
      "Today: 3/8 pomodoros · 75 min")
    XCTAssertEqual(
      StatisticsText.today(pomodoros: 1, goal: 1, minutes: 25, bundle: en),
      "Today: 1/1 pomodoro · 25 min")
    XCTAssertEqual(
      StatisticsText.spokenToday(pomodoros: 3, goal: 8, minutes: 75, bundle: en),
      "Today: 3 of 8 pomodoros, 75 minutes")
    XCTAssertEqual(
      StatisticsText.goalReached(goal: 1, bundle: en), "Daily goal reached: 1 pomodoro today")
    XCTAssertEqual(
      StatisticsText.goalDays(reached: 4, of: 7, bundle: en), "Goal reached on 4 of 7 days")
    XCTAssertEqual(
      StatisticsText.spokenDay(
        "Monday, October 20", pomodoros: 2, minutes: 50, goalReached: true, bundle: en),
      "Monday, October 20: 2 pomodoros, 50 minutes, goal reached")
  }

  func testVietnameseDailyGoalTexts() throws {
    let vi = try bundle("vi")
    XCTAssertEqual(
      StatisticsText.today(pomodoros: 3, goal: 8, minutes: 75, bundle: vi),
      "Hôm nay: 3/8 pomodoro · 75 phút")
    XCTAssertEqual(
      StatisticsText.spokenToday(pomodoros: 3, goal: 8, minutes: 75, bundle: vi),
      "Hôm nay: 3 trên 8 pomodoro, 75 phút")
    XCTAssertEqual(
      StatisticsText.goalReached(goal: 8, bundle: vi), "Đã đạt mục tiêu hôm nay: 8 pomodoro")
    XCTAssertEqual(
      StatisticsText.goalDays(reached: 4, of: 7, bundle: vi), "Đạt mục tiêu 4/7 ngày")
    XCTAssertEqual(
      StatisticsText.spokenDay("Thứ Hai", pomodoros: 2, minutes: 50, goalReached: true, bundle: vi),
      "Thứ Hai: 2 pomodoro, 50 phút, đạt mục tiêu")
  }

  func testVietnameseKeepsOneForm() throws {
    let vi = try bundle("vi")
    XCTAssertEqual(
      StatisticsText.today(pomodoros: 1, minutes: 25, bundle: vi), "Hôm nay: 1 pomodoro · 25 phút")
    XCTAssertEqual(
      StatisticsText.today(pomodoros: 3, minutes: 75, bundle: vi), "Hôm nay: 3 pomodoro · 75 phút")
    XCTAssertEqual(
      StatisticsText.week(pomodoros: 2, minutes: 50, bundle: vi), "Tuần: 2 pomodoro · 50 phút")
    XCTAssertEqual(
      StatisticsText.change(pomodoros: 2, percent: 25, minutes: -20, days: 7, bundle: vi),
      "+2 pomodoro (+25%), \u{2212}20 phút so với 7 ngày trước đó")
    XCTAssertEqual(
      StatisticsText.change(pomodoros: -4, percent: -8, minutes: 10, days: 30, bundle: vi),
      "\u{2212}4 pomodoro (\u{2212}8%), +10 phút so với 30 ngày trước đó")
    XCTAssertEqual(
      StatisticsText.total(pomodoros: 3, minutes: 75, days: 30, bundle: vi),
      "Tháng: 3 pomodoro · 75 phút")
    XCTAssertEqual(
      StatisticsText.spokenDay("Thứ Hai", pomodoros: 1, minutes: 1, bundle: vi),
      "Thứ Hai: 1 pomodoro, 1 phút")
  }
}
