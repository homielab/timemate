//  Created by homielab.com

import XCTest

@testable import TimeMate

final class SleepPreventerTests: XCTestCase {
  func testHeldOnlyWhileFocusSessionRuns() {
    XCTAssertTrue(
      SleepPreventer.shouldHoldAssertion(keepAwake: true, state: .active, sessionType: .focus))
  }

  func testReleasedWhenSettingIsOff() {
    XCTAssertFalse(
      SleepPreventer.shouldHoldAssertion(keepAwake: false, state: .active, sessionType: .focus))
  }

  func testReleasedWhenIdleOrPaused() {
    for state in [PomodoroState.idle, .paused] {
      XCTAssertFalse(
        SleepPreventer.shouldHoldAssertion(keepAwake: true, state: state, sessionType: .focus))
    }
  }

  func testReleasedDuringBreaks() {
    for type in [SessionType.shortBreak, .longBreak] {
      XCTAssertFalse(
        SleepPreventer.shouldHoldAssertion(keepAwake: true, state: .active, sessionType: type))
    }
  }
}
