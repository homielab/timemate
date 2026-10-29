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
    timer = makeTimer(focus: 1200)
    timer.startTimer()
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(1200))
    advanceClock(by: 600)
    timer.handleTick()
    XCTAssertEqual(timer.timeRemaining, 600)
    XCTAssertEqual(timer.progress, 0.5, accuracy: 0.0001)
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
    // Still counted, but the break that is long gone waits for Start.
    XCTAssertEqual(history.records.count, 1)
    XCTAssertEqual(alertTimer.focusSessionsCompleted, 1)
    XCTAssertEqual(alertTimer.currentSessionType, .shortBreak)
    XCTAssertEqual(alertTimer.state, .idle)
    XCTAssertNil(alertTimer.endDate)
    XCTAssertEqual(alertTimer.timeRemaining, 2)
    XCTAssertFalse(alertTimer.isWaitingToContinue)
    XCTAssertFalse(showsOverlay(alertTimer))
    XCTAssertEqual(sounds(), 0)
    XCTAssertEqual(posts(), 0)
    // A second wake (or the timer's late fire) must not finish the next session.
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    alertTimer.handleTick()
    XCTAssertEqual(alertTimer.currentSessionType, .shortBreak)
    XCTAssertEqual(alertTimer.state, .idle)
    XCTAssertEqual(alertTimer.timeRemaining, 2)
    XCTAssertEqual(alertTimer.focusSessionsCompleted, 1)
    XCTAssertEqual(history.records.count, 1)
  }

  func testWakeAfterLongSleepThroughBreakDoesNotOpenBreakScreen() {
    timer = makeTimer(focus: 3, short: 60, keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    advanceClock(by: 3600)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(history.records.count, 2)
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .idle)
    XCTAssertFalse(showsOverlay(timer))
  }

  func testWakeJustWithinGracePeriodStillStartsNextSession() {
    timer = makeTimer(focus: 3)
    timer.startTimer()
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    advanceClock(by: 3 + PomodoroTimer.overdueGracePeriod)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(history.records.count, 1)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
    XCTAssertTrue(showsOverlay(timer))
  }

  private func showsOverlay(_ timer: PomodoroTimer) -> Bool {
    BreakOverlayRules.shouldShowOverlay(
      state: timer.state, sessionType: timer.currentSessionType,
      isWaiting: timer.isWaitingToContinue, isPostponed: timer.isBreakPostponed, enabled: true)
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
    // The notification scheduled for the session's end has shown by now:
    // posting it again on wake would show it twice.
    XCTAssertEqual(posts(), 0)
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
    timer = makeTimer(focus: 1440)
    timer.startTimer()
    runTicks(timer, 20)
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    XCTAssertEqual(timer.state, .paused)
    advanceClock(by: 40 * 60)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 1420)
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

  func testPauseOnSleepLeavesABreakAloneWhenScreenLocksOrSleeps() {
    defaults.set(true, forKey: SettingsKey.pauseOnSleep)
    timer = makeTimer(focus: 3, short: 60)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    let endDate = timer.endDate
    lockScreen()
    workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.endDate, endDate)
    XCTAssertTrue(showsOverlay(timer))
  }

  func testPauseOnSleepBreakKeepsCountingThroughSleepAndShowsOverlayOnUnlock() {
    // The hand check: in Debug minutes are seconds — a 1-minute break locked for
    // 20 seconds wakes with 40 s left and the break screen back.
    defaults.set(true, forKey: SettingsKey.pauseOnSleep)
    timer = makeTimer(focus: 3, short: 60)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.timeRemaining, 60)
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    advanceClock(by: 20)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.timeRemaining, 40)
    XCTAssertTrue(showsOverlay(timer))
  }

  func testPauseOnSleepBreakEndedDuringLongSleepMovesOnAsUsual() {
    defaults.set(true, forKey: SettingsKey.pauseOnSleep)
    timer = makeTimer(focus: 3, short: 60, keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    advanceClock(by: 3600)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(history.records.count, 2)
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .idle)
    XCTAssertFalse(showsOverlay(timer))
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

  // MARK: - Stale cycle

  /// Runs three focus sessions (and the breaks between them) with auto-start
  /// off, leaving the timer idle on the fourth focus session.
  private func completeThreeFocusSessions() {
    timer = makeTimer(autoStart: false)
    for _ in 0..<3 {
      timer.startTimer()
      finishSession(timer)
      timer.startTimer()
      finishSession(timer)
    }
    XCTAssertEqual(timer.focusSessionsCompleted, 3)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .idle)
  }

  func testStartAfterTenIdleHoursBeginsAFreshCycle() {
    completeThreeFocusSessions()
    advanceClock(by: 10 * 3600)
    timer.startTimer()
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
    XCTAssertEqual(timer.currentSessionType, .focus)
    finishSession(timer)
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
  }

  func testStartWithinTheHourKeepsTheCycle() {
    completeThreeFocusSessions()
    advanceClock(by: 3600)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .longBreak)
  }

  func testStaleIdleBreakStartsOverOnFocus() {
    timer = makeTimer(autoStart: false)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    advanceClock(by: 10 * 3600)
    timer.startTimer()
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
  }

  /// Three focus sessions, then the third short break waits on the break screen.
  private func waitAfterThreeFocusSessions() {
    timer = makeTimer(keepBreakOpen: true)
    timer.startTimer()
    for round in 0..<3 {
      if round > 0 { timer.continueWork() }
      finishSession(timer)  // focus -> short break, auto-started
      finishSession(timer)  // short break waits on the break screen
    }
    XCTAssertTrue(timer.isWaitingToContinue)
    XCTAssertEqual(timer.focusSessionsCompleted, 3)
  }

  func testContinueWorkAfterAStaleWaitingBreakStartsAFreshCycle() {
    waitAfterThreeFocusSessions()
    advanceClock(by: 10 * 3600)
    timer.continueWork()
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
  }

  func testContinueWorkAfterARecentWaitingBreakKeepsTheCycle() {
    waitAfterThreeFocusSessions()
    advanceClock(by: 3600)
    timer.continueWork()
    XCTAssertEqual(timer.focusSessionsCompleted, 3)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .longBreak)
  }

  func testContinueWorkJustAfterMidnightKeepsTheCycle() {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    currentTime = utc.date(
      from: DateComponents(year: 2026, month: 3, day: 10, hour: 23, minute: 45))!
    timer = makeTimer(keepBreakOpen: true)
    timer.startTimer()
    for round in 0..<3 {
      if round > 0 {
        advanceClock(by: 6 * 60)
        timer.continueWork()
      }
      finishSession(timer)  // focus -> short break, auto-started
      finishSession(timer)  // short break waits on the break screen
    }
    XCTAssertTrue(timer.isWaitingToContinue)
    XCTAssertEqual(timer.focusSessionsCompleted, 3)
    let afterMidnight = utc.date(
      from: DateComponents(year: 2026, month: 3, day: 11, hour: 0, minute: 2))!
    advanceClock(by: afterMidnight.timeIntervalSince(currentTime))
    timer.continueWork()
    XCTAssertEqual(timer.focusSessionsCompleted, 3)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .longBreak)
  }

  func testResumingAfterAShortPauseKeepsTheCycle() {
    completeThreeFocusSessions()
    timer.startTimer()
    runTicks(timer, 1)
    timer.pauseTimer()
    advanceClock(by: 3600)
    timer.startTimer()
    XCTAssertEqual(timer.focusSessionsCompleted, 3)
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .longBreak)
  }

  func testResumingAfterAStalePauseStartsAFreshCycleAndKeepsTheTimeLeft() {
    completeThreeFocusSessions()
    timer.startTimer()
    runTicks(timer, 1)
    timer.pauseTimer()
    let left = timer.timeRemaining
    advanceClock(by: 10 * 3600)
    timer.startTimer()
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, left)
    finishSession(timer)
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
  }

  func testStalePauseAcrossARelaunchStartsAFreshCycleOnResume() {
    completeThreeFocusSessions()
    timer.startTimer()
    runTicks(timer, 1)
    timer.pauseTimer()
    let relaunched = relaunch(after: 10 * 3600, focus: 3, autoStart: false)
    XCTAssertEqual(relaunched.state, .paused)
    XCTAssertEqual(relaunched.focusSessionsCompleted, 3)
    relaunched.startTimer()
    XCTAssertEqual(relaunched.focusSessionsCompleted, 0)
  }

  func testOldPausedSnapshotWithoutPauseTimeKeepsTheCycleOnResume() throws {
    completeThreeFocusSessions()
    timer.startTimer()
    runTicks(timer, 1)
    timer.pauseTimer()
    var saved = try XCTUnwrap(TimerSnapshot.load(from: defaults))
    XCTAssertNotNil(saved.pausedAt)
    saved.pausedAt = nil
    saved.save(to: defaults)
    let relaunched = relaunch(after: 10 * 3600, focus: 3, autoStart: false)
    relaunched.startTimer()
    XCTAssertEqual(relaunched.focusSessionsCompleted, 3)
  }

  func testStaleCycleIsResetWhenTheAppOpensIdle() {
    completeThreeFocusSessions()
    let relaunched = relaunch(after: 10 * 3600, focus: 3, autoStart: false)
    XCTAssertEqual(relaunched.focusSessionsCompleted, 0)
    XCTAssertEqual(relaunched.currentSessionType, .focus)
    XCTAssertEqual(relaunched.state, .idle)
  }

  func testRecentCycleSurvivesARelaunch() {
    completeThreeFocusSessions()
    let relaunched = relaunch(after: 600, focus: 3, autoStart: false)
    XCTAssertEqual(relaunched.focusSessionsCompleted, 3)
  }

  func testPausedSessionKeepsItsCycleAcrossARelaunch() {
    completeThreeFocusSessions()
    timer.startTimer()
    runTicks(timer, 1)
    timer.pauseTimer()
    let relaunched = relaunch(after: 10 * 3600, focus: 3, autoStart: false)
    XCTAssertEqual(relaunched.state, .paused)
    XCTAssertEqual(relaunched.focusSessionsCompleted, 3)
  }

  func testSnapshotWithoutLastActivityStillDecodes() throws {
    let snapshot = TimerSnapshot(
      state: .paused, sessionType: .focus, endDate: nil, remaining: 5, totalDuration: 10,
      focusSessionsCompleted: 2, isBreakPostponed: false, isWaitingToContinue: false,
      label: "Write", lastActivity: currentTime)
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
    json.removeValue(forKey: "lastActivity")
    let old = try JSONDecoder().decode(
      TimerSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    XCTAssertNil(old.lastActivity)
    XCTAssertEqual(old.focusSessionsCompleted, 2)
    XCTAssertTrue(old.isValid)
  }
}
