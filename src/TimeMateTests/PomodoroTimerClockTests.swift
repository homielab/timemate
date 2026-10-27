//  Created by homielab.com

import AppKit
import XCTest

@testable import TimeMate

/// The wall clock, sleep, screen lock and system clock changes.
final class PomodoroTimerClockTests: TimerTestCase {
  // MARK: - Injected clock

  func testInjectedClockStampsEachTick() {
    let first = Date(timeIntervalSince1970: 5_000)
    let second = first.addingTimeInterval(7)
    currentTime = first
    timer.startTimer()
    timer.handleTick()
    XCTAssertEqual(timer.lastTickAt, first)
    currentTime = second
    timer.handleTick()
    XCTAssertEqual(timer.lastTickAt, second)
  }

  // MARK: - Wall-clock end date (sleep / App Nap)

  func testClockJumpOfTenMinutesDropsRemainingByTenMinutes() {
    timer = makeTimer(focus: 1500)
    timer.startTimer()
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(1500))
    advanceClock(by: 600)
    timer.handleTick()
    XCTAssertEqual(timer.timeRemaining, 900)
    XCTAssertEqual(timer.progress, 0.6, accuracy: 0.0001)
    XCTAssertEqual(timer.state, .active)
  }

  func testDelayedTicksDoNotStretchTheSession() {
    timer = makeTimer(focus: 10)
    timer.startTimer()
    // App Nap: only two ticks get through over the whole session length.
    advanceClock(by: 4)
    timer.handleTick()
    XCTAssertEqual(timer.timeRemaining, 6)
    advanceClock(by: 6)
    timer.handleTick()
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
  }

  func testJumpPastEndDateFinishesSessionExactlyOnce() {
    timer = makeTimer(autoStart: false)
    var sessionChanges = 0
    let cancellable = timer.$currentSessionType.dropFirst().sink { _ in sessionChanges += 1 }
    timer.startTimer()
    advanceClock(by: 3600)
    timer.handleTick()
    timer.handleTick()
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(sessionChanges, 1)
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(timer.timeRemaining, 2)
    cancellable.cancel()
  }

  func testWakeAfterLongSleepFinishesSessionOnceAndSilently() {
    let (alertTimer, sounds, posts) = makeAlertTimer()
    alertTimer.startTimer()
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    advanceClock(by: 3600)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(alertTimer.focusSessionsCompleted, 1)
    XCTAssertEqual(alertTimer.currentSessionType, .shortBreak)
    XCTAssertEqual(alertTimer.state, .active)
    XCTAssertEqual(alertTimer.timeRemaining, 2)
    XCTAssertEqual(sounds(), 0)
    XCTAssertEqual(posts(), 0)
    // A second wake (or the timer's late fire) must not finish the next session.
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    alertTimer.handleTick()
    XCTAssertEqual(alertTimer.currentSessionType, .shortBreak)
    XCTAssertEqual(alertTimer.timeRemaining, 2)
    XCTAssertEqual(alertTimer.focusSessionsCompleted, 1)
  }

  func testWakeAfterShortSleepPastTheEndStillAlerts() {
    let (alertTimer, sounds, posts) = makeAlertTimer()
    alertTimer.startTimer()
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    advanceClock(by: 120)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(alertTimer.focusSessionsCompleted, 1)
    XCTAssertEqual(alertTimer.currentSessionType, .shortBreak)
    XCTAssertEqual(sounds(), 1)
    XCTAssertEqual(posts(), 1)
  }

  func testWakeBeforeEndDateShowsRealRemainingTime() {
    timer = makeTimer(focus: 120)
    timer.startTimer()
    runTicks(timer, 5)
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    advanceClock(by: 60)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(timer.timeRemaining, 55)
    XCTAssertEqual(timer.state, .active)
  }

  func testWakeWhilePausedKeepsRemainingTime() {
    timer = makeTimer(focus: 120)
    timer.startTimer()
    runTicks(timer, 20)
    timer.pauseTimer()
    advanceClock(by: 600)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 100)
  }

  // MARK: - Pause on sleep or screen lock

  private func lockScreen() {
    distributedCenter.post(
      name: Notification.Name(PomodoroTimer.screenLockedNotificationName), object: nil)
  }

  func testPauseOnSleepOffKeepsCountingThroughSleep() {
    timer = makeTimer(focus: 120)
    timer.startTimer()
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    lockScreen()
    workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    XCTAssertEqual(timer.state, .active)
    advanceClock(by: 60)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 60)
  }

  func testPauseOnSleepKeepsSessionPausedAfterLongSleep() {
    defaults.set(true, forKey: SettingsKey.pauseOnSleep)
    timer = makeTimer(focus: 3000)
    timer.startTimer()
    runTicks(timer, 20)
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    XCTAssertEqual(timer.state, .paused)
    advanceClock(by: 40 * 60)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 2980)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertTrue(history.records.isEmpty)
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
  }

  func testPauseOnSleepPausesWhenScreenLocksOrSleeps() {
    defaults.set(true, forKey: SettingsKey.pauseOnSleep)
    timer = makeTimer(focus: 120)
    timer.startTimer()
    lockScreen()
    XCTAssertEqual(timer.state, .paused)
    timer.startTimer()
    XCTAssertEqual(timer.state, .active)
    workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    XCTAssertEqual(timer.state, .paused)
  }

  func testPauseOnSleepLeavesIdleTimerAlone() {
    defaults.set(true, forKey: SettingsKey.pauseOnSleep)
    lockScreen()
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    XCTAssertEqual(timer.state, .idle)
  }

  func testPausedBySleepSurvivesRelaunch() {
    defaults.set(true, forKey: SettingsKey.pauseOnSleep)
    timer = makeTimer(focus: 120)
    timer.startTimer()
    runTicks(timer, 20)
    lockScreen()
    advanceClock(by: 3600)
    let relaunched = makeTimer(focus: 120)
    XCTAssertEqual(relaunched.state, .paused)
    XCTAssertEqual(relaunched.timeRemaining, 100)
  }

  // MARK: - System clock changes

  func testClockSetForwardKeepsTheRemainingTime() {
    timer = makeTimer(focus: 600)
    timer.startTimer()
    runTicks(timer, 10)
    setSystemClock(by: 3600)
    timer.handleSystemClockChange()
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.timeRemaining, 590)
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(590))
    XCTAssertTrue(history.records.isEmpty)
  }

  func testClockSetBackDoesNotStretchTheSession() {
    timer = makeTimer(focus: 600)
    timer.startTimer()
    runTicks(timer, 10)
    setSystemClock(by: -7200)
    timer.handleSystemClockChange()
    XCTAssertEqual(timer.timeRemaining, 590)
    runTicks(timer, 590)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
  }

  func testClockChangeIsSavedForTheNextLaunch() {
    timer = makeTimer(focus: 600)
    timer.startTimer()
    setSystemClock(by: 3600)
    timer.handleSystemClockChange()
    let relaunched = relaunch(after: 100, focus: 600)
    XCTAssertEqual(relaunched.state, .active)
    XCTAssertEqual(relaunched.timeRemaining, 500)
  }

  func testClockChangeWhilePausedKeepsThePausedTime() {
    timer = makeTimer(focus: 600)
    timer.startTimer()
    runTicks(timer, 10)
    timer.pauseTimer()
    setSystemClock(by: 3600)
    timer.handleSystemClockChange()
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 590)
  }

  func testPostedClockChangeNotificationMovesTheEndDate() {
    timer = makeTimer(focus: 600)
    timer.startTimer()
    setSystemClock(by: 3600)
    clockCenter.post(name: .NSSystemClockDidChange, object: nil)
    let expected = currentTime.addingTimeInterval(600)
    XCTAssertTrue(waitUntil { timer.endDate == expected })
    XCTAssertEqual(timer.endDate, expected)
  }
}
