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
}
