//  Created by homielab.com

import AppKit
import XCTest

@testable import TimeMate

/// Restoring a session after the app quits and opens again.
final class PomodoroTimerRelaunchTests: TimerTestCase {
  func testRestoredBreakIsNotAutoStartedOnLaunch() {
    timer = makeTimer(focus: 300, autoStart: false)
    timer.startTimer()
    let restored = relaunch(after: 400, autoStart: false)
    XCTAssertEqual(restored.currentSessionType, .shortBreak)
    XCTAssertEqual(restored.state, .idle)
    XCTAssertFalse(
      LaunchBehavior.shouldAutoStartOnLaunch(
        enabled: true, state: restored.state, sessionType: restored.currentSessionType,
        isWaiting: restored.isWaitingToContinue))
  }

  func testRunningSessionKeepsCountingAfterRelaunch() {
    timer = makeTimer(focus: 300)
    timer.startTimer()
    let endDate = timer.endDate

    let relaunched = relaunch(after: 120)
    XCTAssertEqual(relaunched.state, .active)
    XCTAssertEqual(relaunched.currentSessionType, .focus)
    XCTAssertEqual(relaunched.endDate, endDate)
    XCTAssertEqual(relaunched.timeRemaining, 180)
    XCTAssertEqual(relaunched.progress, 0.6, accuracy: 0.001)
    XCTAssertTrue(history.records.isEmpty)
  }

  func testPausedSessionStaysPausedAfterRelaunch() {
    timer = makeTimer(focus: 3, short: 2, interval: 4)
    timer.startTimer()
    finishSession(timer)  // one focus done, short break running
    timer.skipSession()  // focus again
    runTicks(timer, 1)
    timer.pauseTimer()

    let relaunched = relaunch(after: 600, focus: 3)
    XCTAssertEqual(relaunched.state, .paused)
    XCTAssertNil(relaunched.endDate)
    XCTAssertEqual(relaunched.timeRemaining, 2)
    XCTAssertEqual(relaunched.focusSessionsCompleted, 1)

    relaunched.startTimer()
    XCTAssertEqual(relaunched.timeRemaining, 2)
    XCTAssertEqual(relaunched.state, .active)
  }

  func testSessionThatEndedWhileClosedIsRecordedAndNextSessionWaits() {
    timer = makeTimer(focus: 300, autoStart: false)
    timer.startTimer()
    let endDate = timer.endDate!

    let relaunched = relaunch(after: 3 * 3600, autoStart: false)
    XCTAssertEqual(history.records.count, 1)
    XCTAssertEqual(history.records.first?.kind, .focus)
    XCTAssertEqual(history.records.first?.end, endDate)
    XCTAssertEqual(history.records.first?.duration, 300)
    XCTAssertEqual(relaunched.currentSessionType, .shortBreak)
    XCTAssertEqual(relaunched.focusSessionsCompleted, 1)
    XCTAssertEqual(relaunched.state, .idle)
    XCTAssertEqual(relaunched.timeRemaining, 2)
  }

  func testSessionThatEndedWhileClosedStartsNextWhenAutoStartIsOn() {
    timer = makeTimer(focus: 300)
    timer.startTimer()

    let relaunched = relaunch(after: 3600)
    XCTAssertEqual(history.records.count, 1)
    XCTAssertEqual(relaunched.currentSessionType, .shortBreak)
    XCTAssertEqual(relaunched.state, .active)
    XCTAssertEqual(relaunched.endDate, currentTime.addingTimeInterval(2))
  }

  func testBreakThatEndedWhileClosedDoesNotOpenBreakScreen() {
    timer = makeTimer(focus: 3, short: 60, keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)

    let relaunched = relaunch(after: 3600, focus: 3, keepBreakOpen: true)
    XCTAssertEqual(history.records.count, 2)
    XCTAssertFalse(relaunched.isWaitingToContinue)
    XCTAssertEqual(relaunched.currentSessionType, .focus)
    XCTAssertEqual(relaunched.state, .idle)
  }

  func testWaitingBreakScreenMovesToNextSessionAfterRelaunch() {
    timer = makeTimer(focus: 3, short: 2, keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    finishSession(timer)
    XCTAssertTrue(timer.isWaitingToContinue)

    let relaunched = relaunch(after: 60, focus: 3, keepBreakOpen: true)
    XCTAssertFalse(relaunched.isWaitingToContinue)
    XCTAssertEqual(relaunched.currentSessionType, .focus)
    XCTAssertEqual(relaunched.state, .idle)
    XCTAssertEqual(relaunched.focusSessionsCompleted, 1)
    XCTAssertEqual(history.records.count, 2)
  }

  func testPostponedBreakSurvivesRelaunch() {
    timer = makeTimer(focus: 3, short: 2)
    timer.startTimer()
    finishSession(timer)
    timer.postponeBreak(minutes: 10)

    let relaunched = relaunch(after: 4, focus: 3)
    XCTAssertTrue(relaunched.isBreakPostponed)
    XCTAssertEqual(relaunched.state, .active)
    XCTAssertEqual(relaunched.timeRemaining, 6)

    let due = relaunch(after: 60, focus: 3)
    XCTAssertFalse(due.isBreakPostponed)
    XCTAssertEqual(due.currentSessionType, .shortBreak)
    XCTAssertEqual(due.state, .idle)
    XCTAssertEqual(due.timeRemaining, 2)
    XCTAssertEqual(history.records.count, 1)
  }

  func testDamagedSnapshotIsIgnored() {
    for damaged: Any in [
      Data("not json".utf8), "text",
      try! JSONEncoder().encode(
        TimerSnapshot(
          state: .active, sessionType: .focus, endDate: nil, remaining: 5,
          totalDuration: 10, focusSessionsCompleted: 2, isBreakPostponed: false,
          isWaitingToContinue: false)),
    ] {
      timer = nil
      defaults.set(damaged, forKey: SettingsKey.timerSnapshot)
      timer = makeTimer()
      XCTAssertEqual(timer.state, .idle)
      XCTAssertEqual(timer.currentSessionType, .focus)
      XCTAssertEqual(timer.focusSessionsCompleted, 0)
      XCTAssertEqual(timer.timeRemaining, 3)
      XCTAssertNotNil(TimerSnapshot.load(from: defaults))
    }
  }

  func testClockSetBackCannotStretchRestoredSession() {
    timer = makeTimer(focus: 300)
    timer.startTimer()

    let relaunched = relaunch(after: -3600)
    XCTAssertEqual(relaunched.state, .active)
    XCTAssertEqual(relaunched.timeRemaining, 300)
  }
}
