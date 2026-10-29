//  Created by homielab.com

import XCTest

@testable import TimeMate

final class TodaySummaryTests: XCTestCase {
  private let en = Locale(identifier: "en_US")

  private func bundle(_ localization: String) throws -> Bundle {
    let path = try XCTUnwrap(
      Bundle(for: PomodoroTimer.self).path(forResource: localization, ofType: "lproj"))
    return try XCTUnwrap(Bundle(path: path))
  }

  private func summary(
    _ pomodoros: Int, goal: Int?, streak: Int, bundle: Bundle, locale: Locale
  ) -> TodaySummary {
    TodaySummary(
      pomodoros: pomodoros, minutes: pomodoros * 25, goal: goal, streak: { streak },
      bundle: bundle, locale: locale)
  }

  func testGoalOffShowsPlainLineAndNeverCountsTheStreak() throws {
    var counted = false
    let s = TodaySummary(
      pomodoros: 3, minutes: 75, goal: DailyGoal.off,
      streak: {
        counted = true
        return 5
      },
      bundle: try bundle("en"), locale: en)
    XCTAssertFalse(counted)
    XCTAssertFalse(s.hasGoal)
    XCTAssertFalse(s.reached)
    XCTAssertFalse(s.showsStreak)
    XCTAssertEqual(s.progress, 0)
    XCTAssertEqual(s.visibleText, "Today: 3 pomodoros · 75 min")
    XCTAssertEqual(s.accessibilityLabel, s.visibleText)
    XCTAssertFalse(
      TodaySummary(pomodoros: 1, minutes: 25, goal: nil, streak: { 1 }, bundle: .main).hasGoal)
  }

  func testGoalNotReached() throws {
    let s = summary(3, goal: 8, streak: 0, bundle: try bundle("en"), locale: en)
    XCTAssertTrue(s.hasGoal)
    XCTAssertFalse(s.reached)
    XCTAssertEqual(s.progress, 3.0 / 8.0, accuracy: 0.0001)
    XCTAssertEqual(s.visibleText, "Today: 3/8 pomodoros · 75 min")
    XCTAssertEqual(s.accessibilityLabel, "Today: 3 of 8 pomodoros, 75 minutes")
  }

  func testGoalReachedSaysSoInTheLabel() throws {
    let s = summary(9, goal: 8, streak: 0, bundle: try bundle("en"), locale: en)
    XCTAssertTrue(s.reached)
    XCTAssertEqual(s.progress, 1)
    XCTAssertEqual(s.accessibilityLabel, "Today: 9 of 8 pomodoros, 225 minutes, goal reached")
  }

  func testZeroStreakIsHidden() throws {
    let s = summary(2, goal: 4, streak: 0, bundle: try bundle("en"), locale: en)
    XCTAssertFalse(s.showsStreak)
    XCTAssertEqual(s.streakText, "")
    XCTAssertFalse(s.accessibilityLabel.contains("Streak"))
  }

  func testStreakIsShownAndSpoken() throws {
    let s = summary(4, goal: 4, streak: 3, bundle: try bundle("en"), locale: en)
    XCTAssertTrue(s.showsStreak)
    XCTAssertEqual(s.streak, 3)
    XCTAssertEqual(s.streakText, "Streak: 3 days")
    XCTAssertEqual(
      s.accessibilityLabel, "Today: 4 of 4 pomodoros, 100 minutes, goal reached, Streak: 3 days")
  }

  func testOutOfRangeGoalIsClamped() throws {
    let s = summary(1, goal: 99, streak: 0, bundle: try bundle("en"), locale: en)
    XCTAssertEqual(s.goal, DailyGoal.range.upperBound)
  }

  func testVietnameseLabel() throws {
    let s = summary(
      4, goal: 4, streak: 2, bundle: try bundle("vi"), locale: Locale(identifier: "vi_VN"))
    XCTAssertTrue(s.accessibilityLabel.contains("đạt mục tiêu"), s.accessibilityLabel)
    XCTAssertTrue(s.accessibilityLabel.hasSuffix("Chuỗi: 2 ngày"), s.accessibilityLabel)
    XCTAssertFalse(s.accessibilityLabel.contains("goal reached"), s.accessibilityLabel)
  }
}
