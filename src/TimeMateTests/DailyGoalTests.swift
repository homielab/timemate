//  Created by homielab.com

import UserNotifications
import XCTest

@testable import TimeMate

final class DailyGoalTests: XCTestCase {
  // MARK: - Pure logic

  func testSanitizedTreatsMissingAndNegativeAsOffAndCapsAtTheRange() {
    XCTAssertEqual(DailyGoal.sanitized(nil), DailyGoal.off)
    XCTAssertEqual(DailyGoal.sanitized(-3), DailyGoal.off)
    XCTAssertEqual(DailyGoal.sanitized(0), DailyGoal.off)
    XCTAssertEqual(DailyGoal.sanitized(8), 8)
    XCTAssertEqual(DailyGoal.sanitized(99), DailyGoal.range.upperBound)
  }

  func testProgressIsAFractionCappedAtOne() {
    XCTAssertEqual(DailyGoal.progress(completed: 0, goal: 8), 0)
    XCTAssertEqual(DailyGoal.progress(completed: 6, goal: 8), 0.75)
    XCTAssertEqual(DailyGoal.progress(completed: 8, goal: 8), 1)
    XCTAssertEqual(DailyGoal.progress(completed: 12, goal: 8), 1)
    XCTAssertEqual(DailyGoal.progress(completed: 5, goal: 0), 0)
  }

  func testIsReachedNeedsAGoal() {
    XCTAssertFalse(DailyGoal.isReached(completed: 1, goal: 2))
    XCTAssertTrue(DailyGoal.isReached(completed: 2, goal: 2))
    XCTAssertTrue(DailyGoal.isReached(completed: 3, goal: 2))
    XCTAssertFalse(DailyGoal.isReached(completed: 0, goal: 0))
    XCTAssertFalse(DailyGoal.isReached(completed: 5, goal: 0))
  }

  func testJustReachedOnlyWhenCrossingTheGoal() {
    XCTAssertTrue(DailyGoal.justReached(before: 1, after: 2, goal: 2))
    XCTAssertFalse(DailyGoal.justReached(before: 0, after: 1, goal: 2))
    XCTAssertFalse(DailyGoal.justReached(before: 2, after: 3, goal: 2))
    XCTAssertFalse(DailyGoal.justReached(before: 2, after: 2, goal: 2))
    XCTAssertFalse(DailyGoal.justReached(before: 0, after: 1, goal: 0))
  }

  func testWasNotifiedComparesCalendarDays() {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let morning = utc.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 8))!
    let evening = utc.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 23))!
    let nextDay = utc.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 0))!
    XCTAssertFalse(DailyGoal.wasNotified(on: nil, today: morning, calendar: utc))
    XCTAssertTrue(DailyGoal.wasNotified(on: morning, today: evening, calendar: utc))
    XCTAssertFalse(DailyGoal.wasNotified(on: evening, today: nextDay, calendar: utc))
  }

  // MARK: - Notification content

  func testGoalNotificationHasNoButtonsAndNoSound() throws {
    let path = try XCTUnwrap(
      Bundle(for: PomodoroTimer.self).path(forResource: "en", ofType: "lproj"))
    let content = SessionNotification.dailyGoalContent(
      goal: 8, bundle: try XCTUnwrap(Bundle(path: path)))
    XCTAssertEqual(content.subtitle, "Daily goal reached: 8 pomodoros today")
    XCTAssertNil(content.sound)
    XCTAssertEqual(content.categoryIdentifier, "")
    XCTAssertEqual(content.threadIdentifier, SessionNotification.threadIdentifier)
    XCTAssertEqual(
      SessionNotification.dailyGoalRequest(goal: 8).identifier,
      SessionNotification.dailyGoalIdentifier)
  }

  // MARK: - Timer

  private static let suiteName = "TimeMateDailyGoalTests"
  private var defaults: UserDefaults!
  private var calendar = Calendar(identifier: .gregorian)
  private var currentTime = Date()
  private var history: SessionHistory!
  private var posted: [UNNotificationRequest] = []

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    currentTime = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 9))!
    history = SessionHistory(
      fileURL: nil, now: { [unowned self] in self.currentTime }, calendar: calendar,
      notificationCenter: NotificationCenter())
    posted = []
  }

  override func tearDown() {
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  /// Debug builds treat minutes as seconds: focus lasts 3 ticks, short break 2.
  private func makeTimer(goal: Int?, notificationsEnabled: Bool = true) -> PomodoroTimer {
    defaults.set(3, forKey: SettingsKey.focusDuration)
    defaults.set(2, forKey: SettingsKey.shortBreakDuration)
    defaults.set(4, forKey: SettingsKey.longBreakDuration)
    defaults.set(4, forKey: SettingsKey.longBreakInterval)
    defaults.set(true, forKey: SettingsKey.autoStartNextSession)
    defaults.set(false, forKey: SettingsKey.keepBreakScreenOpen)
    defaults.set(notificationsEnabled, forKey: SettingsKey.notificationsEnabled)
    defaults.set(0.0, forKey: SettingsKey.alarmVolume)
    if let goal {
      defaults.set(goal, forKey: SettingsKey.dailyGoal)
    }
    return PomodoroTimer(
      defaults: defaults,
      now: { [unowned self] in self.currentTime },
      workspaceNotificationCenter: NotificationCenter(),
      history: history,
      notificationCenter: NotificationCenter(),
      postNotification: { [unowned self] in self.posted.append($0) }, isFullscreenProbe: { false })
  }

  /// Ticks one second at a time until today's history holds `pomodoros`.
  private func run(_ timer: PomodoroTimer, until pomodoros: Int) {
    if timer.state != .active { timer.startTimer() }
    var ticks = 0
    while history.todayTotals().pomodoros < pomodoros, ticks < 1_000 {
      currentTime = currentTime.addingTimeInterval(1)
      timer.handleTick()
      ticks += 1
    }
    XCTAssertEqual(history.todayTotals().pomodoros, pomodoros)
  }

  private var goalNotifications: [UNNotificationRequest] {
    posted.filter { $0.identifier == SessionNotification.dailyGoalIdentifier }
  }

  func testReachingTheGoalNotifiesExactlyOnce() {
    let timer = makeTimer(goal: 2)
    run(timer, until: 1)
    XCTAssertTrue(goalNotifications.isEmpty)
    run(timer, until: 2)
    XCTAssertEqual(goalNotifications.count, 1)
    run(timer, until: 4)
    XCTAssertEqual(goalNotifications.count, 1)
    // Every session-complete notification still goes out.
    XCTAssertGreaterThan(posted.count - goalNotifications.count, 4)
  }

  func testNoGoalMeansNoGoalNotification() {
    let timer = makeTimer(goal: nil)
    run(timer, until: 3)
    XCTAssertTrue(goalNotifications.isEmpty)
    XCTAssertFalse(posted.isEmpty)
  }

  func testNotificationsOffMeansNoGoalNotification() {
    let timer = makeTimer(goal: 1, notificationsEnabled: false)
    run(timer, until: 1)
    XCTAssertTrue(posted.isEmpty)
  }

  func testGoalNotificationStillComesWhenNotificationsAreTurnedBackOn() {
    let timer = makeTimer(goal: 1, notificationsEnabled: false)
    run(timer, until: 1)
    XCTAssertTrue(goalNotifications.isEmpty)
    defaults.set(true, forKey: SettingsKey.notificationsEnabled)
    history.reset()
    run(timer, until: 1)
    XCTAssertEqual(goalNotifications.count, 1)
  }

  func testResettingStatisticsDoesNotNotifyTwiceTheSameDay() {
    let timer = makeTimer(goal: 1)
    run(timer, until: 1)
    history.reset()
    run(timer, until: 1)
    XCTAssertEqual(goalNotifications.count, 1)
  }

  func testTheNextDayNotifiesAgain() {
    let timer = makeTimer(goal: 1)
    run(timer, until: 1)
    timer.stopTimer()
    currentTime = currentTime.addingTimeInterval(24 * 60 * 60)
    run(timer, until: 1)
    XCTAssertEqual(goalNotifications.count, 2)
  }

  func testStreakLineShowsOnlyWithGoalAndStreak() {
    XCTAssertTrue(DailyGoal.showsStreak(streak: 1, goal: 4))
    XCTAssertTrue(DailyGoal.showsStreak(streak: 12, goal: 1))
    XCTAssertFalse(DailyGoal.showsStreak(streak: 0, goal: 4))
    XCTAssertFalse(DailyGoal.showsStreak(streak: 3, goal: DailyGoal.off))
    XCTAssertFalse(DailyGoal.showsStreak(streak: 0, goal: DailyGoal.off))
  }

  func testAccessibilityLabelJoinsTodayAndStreak() {
    XCTAssertEqual(
      DailyGoal.accessibilityLabel(today: "Today: 3 of 4", streak: "Streak: 2 days"),
      "Today: 3 of 4, Streak: 2 days")
    XCTAssertEqual(
      DailyGoal.accessibilityLabel(today: "Today: 3 of 4", streak: nil), "Today: 3 of 4")
  }
}
