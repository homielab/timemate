//  Created by homielab.com

import XCTest

@testable import TimeMate

final class TimerIntentActionsTests: XCTestCase {
  private static let suiteName = "TimeMateIntentTests"

  private var defaults: UserDefaults!
  private var currentTime: Date!
  private var timer: PomodoroTimer!

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
    // Debug builds read minutes as seconds: focus 125 lasts 125 s of the fake clock.
    defaults.set(125, forKey: SettingsKey.focusDuration)
    defaults.set(60, forKey: SettingsKey.shortBreakDuration)
    defaults.set(false, forKey: SettingsKey.notificationsEnabled)
    defaults.set(false, forKey: SettingsKey.autoStartNextSession)
    currentTime = Date(timeIntervalSince1970: 1_000_000)
    timer = PomodoroTimer(
      defaults: defaults, now: { [unowned self] in self.currentTime },
      workspaceNotificationCenter: NotificationCenter())
  }

  override func tearDown() {
    timer.stopTimer()
    timer = nil
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  func testStartStartsAnIdleTimerAndNeverPausesARunningOne() {
    TimerIntentActions.start(timer)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.currentSessionType, .focus)

    TimerIntentActions.start(timer)
    XCTAssertEqual(timer.state, .active)
  }

  func testPauseThenStartResumesWithTheTimeLeft() {
    TimerIntentActions.start(timer)
    currentTime += 20
    timer.handleTick()

    TimerIntentActions.pause(timer)
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 105)

    TimerIntentActions.start(timer)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 105)
  }

  func testPauseDoesNothingWhenIdle() {
    TimerIntentActions.pause(timer)
    XCTAssertEqual(timer.state, .idle)
  }

  func testSkipMovesToTheNextSession() {
    TimerIntentActions.start(timer)
    TimerIntentActions.skip(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
  }

  func testResetStopsTheTimerAndRestartsTheSession() {
    TimerIntentActions.start(timer)
    currentTime += 20
    timer.handleTick()

    TimerIntentActions.reset(timer)

    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.timeRemaining, 125)
  }

  func testResetClearsAWaitingBreakScreen() {
    timer.currentSessionType = .shortBreak
    timer.isWaitingToContinue = true
    TimerIntentActions.reset(timer)
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.state, .idle)
  }

  func testStartContinuesPastAFinishedBreak() {
    timer.currentSessionType = .shortBreak
    timer.isWaitingToContinue = true
    TimerIntentActions.start(timer)
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
  }

  func testMinutesRemainingRoundsUp() {
    XCTAssertEqual(TimerIntentActions.minutesRemaining(timer), 3)
    TimerIntentActions.start(timer)
    currentTime += 66
    timer.handleTick()
    XCTAssertEqual(timer.timeRemaining, 59)
    XCTAssertEqual(TimerIntentActions.minutesRemaining(timer), 1)
  }

  func testStatusTextNamesTheSessionAndState() {
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Focus, not started, 3 min")
    TimerIntentActions.start(timer)
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Focus, running, 3 min left")
    TimerIntentActions.pause(timer)
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Focus, paused, 3 min left")
    timer.currentSessionType = .shortBreak
    timer.isWaitingToContinue = true
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Short Break finished")
    XCTAssertEqual(TimerIntentActions.minutesRemaining(timer), 0)
  }

  // MARK: - Today's progress

  private func makeHistory() -> SessionHistory {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return SessionHistory(
      fileURL: nil, now: { [unowned self] in self.currentTime }, calendar: calendar,
      notificationCenter: NotificationCenter())
  }

  func testProgressWithNoSessions() {
    let progress = TimerIntentActions.todayProgress(history: makeHistory(), goal: 0)
    XCTAssertEqual(progress, .init(completed: 0, goal: nil, focusMinutes: 0))
    XCTAssertFalse(progress.goalReached)
    XCTAssertEqual(TimerIntentActions.progressText(progress), "Today: 0 pomodoros · 0 min")
  }

  func testProgressWithoutAGoalCountsOnlyTodaysFocusSessions() {
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 25 * 60, end: currentTime)
    history.recordCompletedSession(.focus, duration: 25 * 60, end: currentTime)
    history.recordCompletedSession(.shortBreak, duration: 5 * 60, end: currentTime)
    history.recordCompletedSession(
      .focus, duration: 25 * 60, end: currentTime.addingTimeInterval(-2 * 86_400))

    let progress = TimerIntentActions.todayProgress(history: history, goal: DailyGoal.off)

    XCTAssertEqual(progress, .init(completed: 2, goal: nil, focusMinutes: 50))
    XCTAssertFalse(progress.goalReached)
    XCTAssertEqual(TimerIntentActions.progressText(progress), "Today: 2 pomodoros · 50 min")
  }

  func testProgressBelowTheGoal() {
    let history = makeHistory()
    for _ in 0..<3 { history.recordCompletedSession(.focus, duration: 25 * 60, end: currentTime) }

    let progress = TimerIntentActions.todayProgress(history: history, goal: 8)

    XCTAssertEqual(progress, .init(completed: 3, goal: 8, focusMinutes: 75))
    XCTAssertFalse(progress.goalReached)
    XCTAssertEqual(
      TimerIntentActions.progressText(progress), "Today: 3 of 8 pomodoros, 75 minutes")
  }

  func testReachingTheGoalSetsGoalReached() {
    let history = makeHistory()
    for _ in 0..<2 { history.recordCompletedSession(.focus, duration: 25 * 60, end: currentTime) }

    XCTAssertTrue(TimerIntentActions.todayProgress(history: history, goal: 2).goalReached)
    history.recordCompletedSession(.focus, duration: 25 * 60, end: currentTime)
    XCTAssertTrue(TimerIntentActions.todayProgress(history: history, goal: 2).goalReached)
    XCTAssertFalse(TimerIntentActions.todayProgress(history: history, goal: 4).goalReached)
  }

  func testProgressTextMentionsTheStreak() {
    let history = makeHistory()
    for day in 0..<3 {
      let end = currentTime.addingTimeInterval(-Double(day) * 86_400)
      history.recordCompletedSession(.focus, duration: 25 * 60, end: end)
    }

    let progress = TimerIntentActions.todayProgress(history: history, goal: 1)

    XCTAssertEqual(progress.streak, 3)
    XCTAssertEqual(
      TimerIntentActions.progressText(progress),
      "Today: 1 of 1 pomodoro, 25 minutes. Streak: 3 days")
    XCTAssertEqual(TimerIntentActions.todayProgress(history: history, goal: 0).streak, 0)
  }
}
