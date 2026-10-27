//  Created by homielab.com

import XCTest

@testable import TimeMate

final class BreakOverlayRulesTests: XCTestCase {
  private func shows(
    _ state: PomodoroState, _ sessionType: SessionType, isWaiting: Bool = false,
    isPostponed: Bool = false, enabled: Bool = true
  ) -> Bool {
    BreakOverlayRules.shouldShowOverlay(
      state: state, sessionType: sessionType, isWaiting: isWaiting, isPostponed: isPostponed,
      enabled: enabled)
  }

  func testShowsDuringRunningBreaks() {
    XCTAssertTrue(shows(.active, .shortBreak))
    XCTAssertTrue(shows(.active, .longBreak))
  }

  func testHiddenDuringFocus() {
    XCTAssertFalse(shows(.active, .focus))
    XCTAssertFalse(shows(.paused, .focus))
    XCTAssertFalse(shows(.idle, .focus))
  }

  func testHiddenWhileBreakIsPausedOrIdle() {
    XCTAssertFalse(shows(.paused, .shortBreak))
    XCTAssertFalse(shows(.idle, .longBreak))
  }

  func testHiddenWhileBreakIsPostponed() {
    XCTAssertFalse(shows(.active, .shortBreak, isPostponed: true))
    XCTAssertFalse(shows(.active, .longBreak, isPostponed: true))
  }

  func testShowsWhileWaitingToContinue() {
    // The break has ended; the timer is idle on the next focus session.
    XCTAssertTrue(shows(.idle, .focus, isWaiting: true))
    XCTAssertTrue(shows(.idle, .shortBreak, isWaiting: true, isPostponed: true))
  }

  func testNeverShowsWhenTurnedOff() {
    XCTAssertFalse(shows(.active, .shortBreak, enabled: false))
    XCTAssertFalse(shows(.active, .longBreak, enabled: false))
    XCTAssertFalse(shows(.idle, .focus, isWaiting: true, enabled: false))
  }

  func testDoubleEscContinuesAWaitingBreakAndSkipsARunningOne() {
    XCTAssertEqual(
      BreakOverlayRules.escAction(isWaitingToContinue: true, canSkip: true), .continueWork)
    XCTAssertEqual(
      BreakOverlayRules.escAction(isWaitingToContinue: true, canSkip: false), .continueWork)
    XCTAssertEqual(
      BreakOverlayRules.escAction(isWaitingToContinue: false, canSkip: true), .skipSession)
    XCTAssertEqual(BreakOverlayRules.escAction(isWaitingToContinue: false, canSkip: false), .none)
  }
}

final class DoubleEscDetectorTests: XCTestCase {
  private var time = Date(timeIntervalSinceReferenceDate: 1_000)
  private lazy var detector = DoubleEscDetector(now: { [unowned self] in self.time })

  func testSinglePressDoesNothing() {
    XCTAssertFalse(detector.registerPress())
  }

  func testTwoQuickPressesAreADoublePress() {
    XCTAssertFalse(detector.registerPress())
    time += 0.3
    XCTAssertTrue(detector.registerPress())
  }

  func testPressesAtTheIntervalOrSlowerAreNot() {
    XCTAssertFalse(detector.registerPress())
    time += DoubleEscDetector.defaultInterval
    XCTAssertFalse(detector.registerPress())
    time += 2
    XCTAssertFalse(detector.registerPress())
  }

  func testSlowPressStartsANewWindow() {
    XCTAssertFalse(detector.registerPress())
    time += 1
    XCTAssertFalse(detector.registerPress())
    time += 0.2
    XCTAssertTrue(detector.registerPress())
  }

  func testThirdPressAfterADoublePressStartsOver() {
    XCTAssertFalse(detector.registerPress())
    time += 0.1
    XCTAssertTrue(detector.registerPress())
    time += 0.1
    XCTAssertFalse(detector.registerPress())
    time += 0.1
    XCTAssertTrue(detector.registerPress())
  }

  func testCustomInterval() {
    var slow = DoubleEscDetector(interval: 2, now: { [unowned self] in self.time })
    XCTAssertFalse(slow.registerPress())
    time += 1.5
    XCTAssertTrue(slow.registerPress())
  }
}
