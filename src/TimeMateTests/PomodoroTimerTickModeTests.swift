//  Created by homielab.com

import AppKit
import XCTest

@testable import TimeMate

/// Tick modes and the removal of old "session complete" notifications.
final class PomodoroTimerTickModeTests: TimerTestCase {
  // MARK: - Tick mode

  func testAtEndModeSkipsSecondTicksAndCatchesUpWhenShownAgain() {
    timer = makeTimer(focus: 600)
    timer.startTimer()
    timer.tickMode = .atEnd
    advanceClock(by: 100)
    XCTAssertEqual(timer.timeRemaining, 600)
    XCTAssertEqual(timer.secondsRemaining, 500)
    XCTAssertEqual(TimerIntentActions.minutesRemaining(timer), 9)
    timer.tickMode = .everySecond
    XCTAssertEqual(timer.timeRemaining, 500)
  }

  func testEveryMinuteModeCatchesUpWhenSwitchedBackToEverySecond() {
    timer = makeTimer(focus: 600)
    timer.startTimer()
    timer.tickMode = .everyMinute
    advanceClock(by: 100)
    XCTAssertEqual(timer.timeRemaining, 600)
    XCTAssertEqual(timer.secondsRemaining, 500)
    timer.tickMode = .everySecond
    XCTAssertEqual(timer.timeRemaining, 500)
  }

  func testSwitchingTickModeAfterTheEndFinishesTheSessionOnce() {
    timer = makeTimer(focus: 3, autoStart: false)
    timer.startTimer()
    timer.tickMode = .atEnd
    advanceClock(by: 10)
    timer.tickMode = .everySecond
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(history.records.count, 1)
  }

  func testAtEndModeFinishesTheSessionAtItsEnd() {
    timer = makeTimer(focus: 1, autoStart: false)
    timer.tickMode = .atEnd
    timer.startTimer()
    advanceClock(by: 1)
    // The real one-shot timer fires one real second after start (the shortest session).
    XCTAssertTrue(waitUntil(timeout: 5) { timer.currentSessionType == .shortBreak })
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(history.records.count, 1)
  }

  func testWakeAfterAtEndShowsTheRightTimeAndBreakOverlayKeepsTickingEverySecond() {
    timer = makeTimer(focus: 3, short: 1200)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    let overlayMode = TickMode.mode(
      popoverOpen: false, menuBarStyle: .iconOnly, breakOverlayShown: true,
      voiceOverRunning: false)
    XCTAssertEqual(overlayMode, .everySecond)
    // Screen off: only the end wakes the timer; 10 minutes pass unseen.
    timer.tickMode = TickMode.mode(
      popoverOpen: false, menuBarStyle: .minutesSeconds, breakOverlayShown: true,
      voiceOverRunning: true, screenAsleep: true)
    XCTAssertEqual(timer.tickMode, .atEnd)
    advanceClock(by: 600)
    XCTAssertEqual(timer.timeRemaining, 1200)
    // Screen back: the countdown catches up at once and ticks every second.
    timer.tickMode = overlayMode
    XCTAssertEqual(timer.timeRemaining, 600)
    XCTAssertEqual(timer.state, .active)
  }

  // MARK: - Screen inactive

  func testScreenInactivePausesRunningFocusOnlyWithPauseOnSleep() {
    timer = makeTimer(focus: 120)
    timer.startTimer()
    timer.handleScreenInactive()
    XCTAssertEqual(timer.state, .active)
    defaults.set(true, forKey: SettingsKey.pauseOnSleep)
    timer.handleScreenInactive()
    XCTAssertEqual(timer.state, .paused)
  }

  func testScreenInactiveLeavesBreakAndIdleAlone() {
    defaults.set(true, forKey: SettingsKey.pauseOnSleep)
    timer.handleScreenInactive()
    XCTAssertEqual(timer.state, .idle)
    timer = makeTimer(focus: 3, short: 60)
    timer.startTimer()
    finishSession(timer)
    timer.handleScreenInactive()
    XCTAssertEqual(timer.state, .active)
  }

  // MARK: - Old "session complete" notifications

  func testStartSkipResetAndRestartRemoveTheSessionNotification() {
    timer.startTimer()
    XCTAssertEqual(notificationRemovals, 1)
    timer.skipSession()
    XCTAssertEqual(notificationRemovals, 2)
    timer.stopTimer()
    XCTAssertEqual(notificationRemovals, 3)
    timer.restartCycle()
    XCTAssertEqual(notificationRemovals, 4)
  }

  func testIdleTicksPauseAndLaunchDoNotRemoveNotifications() {
    runTicks(timer, 3)
    timer.pauseTimer()
    XCTAssertEqual(notificationRemovals, 0)
    timer.startTimer()
    runTicks(timer, 1)
    timer.pauseTimer()
    XCTAssertEqual(notificationRemovals, 1)
  }

  func testAutoStartKeepsTheNotificationItJustPosted() {
    let (alertTimer, _, posts) = makeAlertTimer()
    alertTimer.startTimer()
    XCTAssertEqual(notificationRemovals, 1)
    runTicks(alertTimer, 3)
    XCTAssertEqual(alertTimer.currentSessionType, .shortBreak)
    XCTAssertEqual(alertTimer.state, .active)
    XCTAssertEqual(posts(), 1)
    XCTAssertEqual(notificationRemovals, 1)
  }

  func testContinueWorkRemovesTheSessionNotification() {
    timer = makeTimer(keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    finishSession(timer)
    XCTAssertTrue(timer.isWaitingToContinue)
    XCTAssertEqual(notificationRemovals, 1)
    timer.continueWork()
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(notificationRemovals, 2)
  }

  func testSkipOnAFreshNotificationStillSkipsTheAutoStartedSession() {
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    timer.handleNotificationAction(.skip)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(notificationRemovals, 2)
  }

  func testStartNextOnAFreshNotificationStartsTheWaitingSession() {
    timer = makeTimer(autoStart: false)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.state, .idle)
    timer.handleNotificationAction(.startNext)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(notificationRemovals, 2)
  }
}
