//  Created by homielab.com

import XCTest

@testable import TimeMate

final class IdlePausePolicyTests: XCTestCase {
  func testSanitizedKeepsOffAndClampsOtherMinutes() {
    XCTAssertEqual(IdlePausePolicy.sanitized(nil), IdlePausePolicy.off)
    XCTAssertEqual(IdlePausePolicy.sanitized(0), IdlePausePolicy.off)
    XCTAssertEqual(IdlePausePolicy.sanitized(-5), IdlePausePolicy.off)
    for minutes in IdlePausePolicy.choices {
      XCTAssertEqual(IdlePausePolicy.sanitized(minutes), minutes)
    }
    XCTAssertEqual(IdlePausePolicy.sanitized(7), 7)
    XCTAssertEqual(IdlePausePolicy.sanitized(500), IdlePausePolicy.validRange.upperBound)
  }

  func testThresholdIsNilWhenOffAndInSessionSecondsOtherwise() {
    XCTAssertNil(IdlePausePolicy.threshold(minutes: IdlePausePolicy.off))
    XCTAssertEqual(
      IdlePausePolicy.threshold(minutes: 5), TimeInterval(PomodoroTimer.seconds(forMinutes: 5)))
  }

  func testPausesOnlyARunningFocusSessionOnceAwayLongEnough() {
    XCTAssertTrue(
      IdlePausePolicy.shouldPause(state: .active, isBreak: false, idleSeconds: 180, threshold: 180))
    XCTAssertFalse(
      IdlePausePolicy.shouldPause(state: .active, isBreak: false, idleSeconds: 179, threshold: 180))
    XCTAssertFalse(
      IdlePausePolicy.shouldPause(state: .active, isBreak: true, idleSeconds: 999, threshold: 180))
    XCTAssertFalse(
      IdlePausePolicy.shouldPause(state: .active, isBreak: false, idleSeconds: 999, threshold: nil))
    for state in [PomodoroState.idle, .paused] {
      XCTAssertFalse(
        IdlePausePolicy.shouldPause(state: state, isBreak: false, idleSeconds: 999, threshold: 180))
    }
  }

  func testRemainingAfterAwayGivesBackTheTimeAway() {
    XCTAssertEqual(
      IdlePausePolicy.remainingAfterAway(
        secondsLeft: 600, idleSeconds: 300, runningFor: 900, totalDuration: 1500), 900)
  }

  func testRemainingAfterAwayGivesBackNoMoreThanTheSessionRan() {
    // Away before the session (re)started: only the time it ran comes back.
    XCTAssertEqual(
      IdlePausePolicy.remainingAfterAway(
        secondsLeft: 1400, idleSeconds: 3600, runningFor: 100, totalDuration: 1500), 1500)
    XCTAssertEqual(
      IdlePausePolicy.remainingAfterAway(
        secondsLeft: 1000, idleSeconds: 3600, runningFor: 100, totalDuration: 1500), 1100)
    XCTAssertEqual(
      IdlePausePolicy.remainingAfterAway(
        secondsLeft: 1000, idleSeconds: 3600, runningFor: .infinity, totalDuration: 1500), 1500)
  }

  func testRemainingAfterAwayIsNotPositiveWhenAwayOnlyAfterTheEnd() {
    XCTAssertLessThanOrEqual(
      IdlePausePolicy.remainingAfterAway(
        secondsLeft: -60, idleSeconds: 30, runningFor: 1560, totalDuration: 1500), 0)
  }

  func testNextCheckWaitsUntilTheThresholdCanBeReached() {
    XCTAssertEqual(IdlePausePolicy.nextCheckDelay(idleSeconds: 0, threshold: 300), 300)
    XCTAssertEqual(IdlePausePolicy.nextCheckDelay(idleSeconds: 120, threshold: 300), 180)
    XCTAssertEqual(
      IdlePausePolicy.nextCheckDelay(idleSeconds: 400, threshold: 300),
      IdlePausePolicy.minimumCheckDelay)
  }

  func testUserIsBackAfterRecentInput() {
    XCTAssertTrue(IdlePausePolicy.userIsBack(idleSeconds: 0.5))
    XCTAssertFalse(IdlePausePolicy.userIsBack(idleSeconds: IdlePausePolicy.backWithin))
  }
}
