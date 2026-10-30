//  Created by homielab.com

import XCTest

@testable import TimeMate

/// "Undo Last Session" takes the session off the current cycle too.
final class PomodoroTimerUndoTests: TimerTestCase {
  private func runFocusAndBreak() {
    timer.startTimer()
    finishSession(timer)
    timer.startTimer()
    finishSession(timer)
  }

  private func undoLast() -> SessionHistory.Record? {
    guard let last = history.lastFocusRecord else { return nil }
    return timer.undoLastFocusSession(matching: last)
  }

  func testUndoAfterThreeSessionsLeavesTwoAndLongBreakAfterTheRealFourth() {
    timer = makeTimer(autoStart: false)
    for _ in 0..<3 { runFocusAndBreak() }
    XCTAssertEqual(timer.focusSessionsCompleted, 3)
    XCTAssertNotNil(undoLast())
    XCTAssertEqual(timer.focusSessionsCompleted, 2)
    XCTAssertEqual(TimerSnapshot.load(from: defaults)?.focusSessionsCompleted, 2)
    runFocusAndBreak()
    XCTAssertEqual(timer.focusSessionsCompleted, 3)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .longBreak)
  }

  private var goalPosts = 0

  /// A timer with 3 s focus, manual start, notifications on and a goal of `goal`
  /// that counts the "goal reached" notifications in `goalPosts`.
  private func makeGoalTimer(goal: Int) {
    defaults.set(3, forKey: SettingsKey.focusDuration)
    defaults.set(2, forKey: SettingsKey.shortBreakDuration)
    defaults.set(false, forKey: SettingsKey.autoStartNextSession)
    defaults.set(true, forKey: SettingsKey.notificationsEnabled)
    defaults.set(0.0, forKey: SettingsKey.alarmVolume)
    defaults.set(goal, forKey: SettingsKey.dailyGoal)
    timer = PomodoroTimer(
      defaults: defaults,
      now: { [weak self] in self?.currentTime ?? Date(timeIntervalSince1970: 0) },
      workspaceNotificationCenter: workspaceCenter,
      distributedNotificationCenter: distributedCenter,
      history: history,
      notificationCenter: clockCenter,
      postNotification: { [weak self] in
        if $0.identifier == SessionNotification.dailyGoalIdentifier { self?.goalPosts += 1 }
      },
      removeSessionNotifications: {},
      removePendingSessionNotification: {},
      playSound: { _, _ in },
      isFullscreenProbe: { false })
  }

  func testUndoTheGoalSessionLetsTheNextOneNotifyAgain() {
    makeGoalTimer(goal: 1)
    runFocusAndBreak()
    XCTAssertEqual(goalPosts, 1)
    XCTAssertNotNil(undoLast())
    runFocusAndBreak()
    XCTAssertEqual(goalPosts, 2)
  }

  func testRaisedGoalReachedSameDayNotifiesAgain() {
    makeGoalTimer(goal: 2)
    for _ in 0..<2 { runFocusAndBreak() }
    XCTAssertEqual(goalPosts, 1)
    defaults.set(3, forKey: SettingsKey.dailyGoal)
    runFocusAndBreak()
    XCTAssertEqual(goalPosts, 2)
    runFocusAndBreak()
    XCTAssertEqual(goalPosts, 2)
  }

  func testResetStatisticsLetsTheGoalNotifyAgain() {
    makeGoalTimer(goal: 1)
    runFocusAndBreak()
    XCTAssertEqual(goalPosts, 1)
    timer.resetStatistics()
    XCTAssertNil(defaults.object(forKey: SettingsKey.dailyGoalNotifiedAt))
    XCTAssertNil(defaults.object(forKey: SettingsKey.dailyGoalNotifiedGoal))
    runFocusAndBreak()
    XCTAssertEqual(goalPosts, 2)
  }

  func testOldDateOnlyFlagStillBlocksThatDay() {
    makeGoalTimer(goal: 1)
    defaults.set(currentTime, forKey: SettingsKey.dailyGoalNotifiedAt)
    runFocusAndBreak()
    XCTAssertEqual(goalPosts, 0)
  }

  func testUndoSessionBeforeLongBreakKeepsCurrentCycle() {
    timer = makeTimer(autoStart: false)
    for _ in 0..<4 { runFocusAndBreak() }
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
    advanceClock(by: 60)
    XCTAssertNotNil(undoLast())
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
    runFocusAndBreak()
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertNotNil(undoLast())
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
  }

  func testUndoSessionBeforeRestartKeepsCurrentCycle() {
    timer = makeTimer(autoStart: false)
    for _ in 0..<2 { runFocusAndBreak() }
    advanceClock(by: 60)
    timer.restartCycle()
    advanceClock(by: 60)
    runFocusAndBreak()
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertNotNil(undoLast())
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
    XCTAssertNotNil(undoLast())
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
  }
}
