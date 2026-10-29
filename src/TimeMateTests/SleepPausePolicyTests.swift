//  Created by homielab.com

import XCTest

@testable import TimeMate

/// "Pause on sleep" stops only a running focus session; a break keeps running.
final class SleepPausePolicyTests: XCTestCase {
  func testActiveFocusSessionWithSettingOnPauses() {
    XCTAssertTrue(SleepPausePolicy.shouldPause(state: .active, isBreak: false, pauseOnSleep: true))
  }

  func testActiveBreakSessionNeverPauses() {
    XCTAssertFalse(SleepPausePolicy.shouldPause(state: .active, isBreak: true, pauseOnSleep: true))
  }

  func testSettingOffPausesNothing() {
    XCTAssertFalse(
      SleepPausePolicy.shouldPause(state: .active, isBreak: false, pauseOnSleep: false))
    XCTAssertFalse(
      SleepPausePolicy.shouldPause(state: .active, isBreak: true, pauseOnSleep: false))
  }

  func testIdleAndPausedSessionsAreNotPausedAgain() {
    for state in [PomodoroState.idle, .paused] {
      XCTAssertFalse(
        SleepPausePolicy.shouldPause(state: state, isBreak: false, pauseOnSleep: true))
      XCTAssertFalse(
        SleepPausePolicy.shouldPause(state: state, isBreak: true, pauseOnSleep: true))
    }
  }

  func testResumesOnlyASleepPauseWithTheSettingOnAndTheScreenUnlocked() {
    XCTAssertTrue(
      SleepPausePolicy.shouldResume(
        state: .paused, pausedBySleep: true, resumeOnReturn: true, isScreenLocked: false,
        pauseIsStale: false))
    XCTAssertFalse(
      SleepPausePolicy.shouldResume(
        state: .paused, pausedBySleep: false, resumeOnReturn: true, isScreenLocked: false,
        pauseIsStale: false))
    XCTAssertFalse(
      SleepPausePolicy.shouldResume(
        state: .paused, pausedBySleep: true, resumeOnReturn: false, isScreenLocked: false,
        pauseIsStale: false))
    XCTAssertFalse(
      SleepPausePolicy.shouldResume(
        state: .paused, pausedBySleep: true, resumeOnReturn: true, isScreenLocked: true,
        pauseIsStale: false))
    XCTAssertFalse(
      SleepPausePolicy.shouldResume(
        state: .paused, pausedBySleep: true, resumeOnReturn: true, isScreenLocked: false,
        pauseIsStale: true))
    for state in [PomodoroState.idle, .active] {
      XCTAssertFalse(
        SleepPausePolicy.shouldResume(
          state: state, pausedBySleep: true, resumeOnReturn: true, isScreenLocked: false,
          pauseIsStale: false))
    }
  }
}
