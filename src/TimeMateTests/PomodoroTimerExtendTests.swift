//  Created by homielab.com

import AppKit
import XCTest

@testable import TimeMate

/// Extending and postponing a break.
final class PomodoroTimerExtendTests: TimerTestCase {
  // MARK: - Extend and postpone a break

  /// Five minutes of session time (seconds-as-minutes in Debug builds).
  private var fiveMinutes: TimeInterval {
    TimeInterval(PomodoroTimer.seconds(forMinutes: 5))
  }

  private func startShortBreak() {
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
  }

  func testSecondsForMinutesMatchesTheBuild() {
    #if DEBUG
      XCTAssertEqual(PomodoroTimer.seconds(forMinutes: 5), 5)
    #else
      XCTAssertEqual(PomodoroTimer.seconds(forMinutes: 5), 300)
    #endif
  }

  func testExtendPushesEndDateOfRunningBreakByFiveMinutes() {
    startShortBreak()
    let endDate = timer.endDate!
    timer.extend(by: 5)
    XCTAssertEqual(timer.endDate, endDate.addingTimeInterval(fiveMinutes))
    XCTAssertEqual(timer.timeRemaining, 2 + Int(fiveMinutes))
    XCTAssertEqual(timer.progress, 1.0)
    XCTAssertEqual(timer.state, .active)
  }

  func testExtendedBreakEndsAtTheNewEndDate() {
    startShortBreak()
    timer.extend(by: 5)
    runTicks(timer, 2 + Int(fiveMinutes) - 1)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    runTicks(timer, 1)
    XCTAssertEqual(timer.currentSessionType, .focus)
  }

  func testExtendWhilePausedAddsToRemainingTime() {
    startShortBreak()
    timer.pauseTimer()
    timer.extend(by: 5)
    XCTAssertEqual(timer.timeRemaining, 2 + Int(fiveMinutes))
    XCTAssertNil(timer.endDate)
    timer.startTimer()
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(2 + fiveMinutes))
  }

  func testExtendDoesNothingDuringFocus() {
    timer.startTimer()
    let endDate = timer.endDate
    timer.extend(by: 5)
    XCTAssertEqual(timer.endDate, endDate)
    XCTAssertEqual(timer.timeRemaining, 3)
  }

  func testExtendOnWaitingBreakScreenStartsFiveMoreMinutes() {
    timer = makeTimer(keepBreakOpen: true)
    startShortBreak()
    finishSession(timer)
    XCTAssertTrue(timer.isWaitingToContinue)
    timer.extend(by: 5)
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(fiveMinutes))
  }

  func testPostponeHidesBreakAndBringsItBackOnTime() {
    startShortBreak()
    timer.postponeBreak(minutes: 3)
    let delay = PomodoroTimer.seconds(forMinutes: 3)
    XCTAssertTrue(timer.isBreakPostponed)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(TimeInterval(delay)))

    runTicks(timer, delay - 1)
    XCTAssertTrue(timer.isBreakPostponed)
    runTicks(timer, 1)
    // The break is back at its full length, not finished or skipped.
    XCTAssertFalse(timer.isBreakPostponed)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 2)
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(2))
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertEqual(history.records.count, 1)  // only the focus session

    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(history.records.count, 2)
  }

  func testPostponedBreakReturnsAfterSleep() {
    startShortBreak()
    timer.postponeBreak(minutes: 1)
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    advanceClock(by: 600)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertFalse(timer.isBreakPostponed)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.timeRemaining, 2)
  }

  func testPostponeOnlyWorksDuringARunningBreak() {
    timer.startTimer()
    timer.postponeBreak(minutes: 1)
    XCTAssertFalse(timer.isBreakPostponed)

    finishSession(timer)
    timer.pauseTimer()
    timer.postponeBreak(minutes: 1)
    XCTAssertFalse(timer.isBreakPostponed)
  }

  func testSkipDuringPostponedBreakGoesToFocus() {
    startShortBreak()
    timer.postponeBreak(minutes: 5)
    timer.skipSession()
    XCTAssertFalse(timer.isBreakPostponed)
    XCTAssertEqual(timer.currentSessionType, .focus)
  }

  func testExtendIsIgnoredWhileBreakIsPostponed() {
    startShortBreak()
    timer.postponeBreak(minutes: 1)
    let endDate = timer.endDate
    timer.extend(by: 5)
    XCTAssertEqual(timer.endDate, endDate)
  }
}
