//  Created by homielab.com

import AppKit
import XCTest

@testable import TimeMate

final class StatusItemMenuTests: XCTestCase {
  func testRightClickAndControlClickOpenTheMenu() {
    XCTAssertTrue(StatusItemMenu.opensMenu(eventType: .rightMouseUp, modifierFlags: []))
    XCTAssertTrue(StatusItemMenu.opensMenu(eventType: .leftMouseUp, modifierFlags: [.control]))
  }

  func testLeftClickTogglesThePopover() {
    XCTAssertFalse(StatusItemMenu.opensMenu(eventType: .leftMouseUp, modifierFlags: []))
    XCTAssertFalse(StatusItemMenu.opensMenu(eventType: .leftMouseUp, modifierFlags: [.command]))
    XCTAssertFalse(StatusItemMenu.opensMenu(eventType: nil, modifierFlags: []))
  }

  func testStartPauseTitleFollowsTheTimerState() {
    XCTAssertEqual(
      StatusItemMenu.startPauseTitle(state: .idle, isWaitingToContinue: false), "Start")
    XCTAssertEqual(
      StatusItemMenu.startPauseTitle(state: .active, isWaitingToContinue: false), "Pause")
    XCTAssertEqual(
      StatusItemMenu.startPauseTitle(state: .paused, isWaitingToContinue: false), "Resume")
    XCTAssertEqual(
      StatusItemMenu.startPauseTitle(state: .idle, isWaitingToContinue: true), "Continue Work")
  }

  func testResetIsDisabledWhileIdle() {
    XCTAssertFalse(StatusItemMenu.isResetEnabled(state: .idle))
    XCTAssertTrue(StatusItemMenu.isResetEnabled(state: .active))
    XCTAssertTrue(StatusItemMenu.isResetEnabled(state: .paused))
  }

  func testAccessibilityLabelIncludesSessionAndTimeRemaining() {
    let label = StatusItemMenu.accessibilityLabel(
      sessionType: .focus, state: .active, secondsRemaining: 12 * 60 + 34,
      isBreakPostponed: false, isWaitingToContinue: false)
    XCTAssertTrue(label.hasPrefix("TimeMate, Focus, "), label)
    XCTAssertTrue(label.hasSuffix(" remaining"), label)
    XCTAssertTrue(label.contains("12"), label)
    XCTAssertTrue(label.contains("34"), label)
    XCTAssertFalse(label.contains(":"), label)
  }

  func testAccessibilityLabelForPausedIdlePostponedAndFinished() {
    let paused = StatusItemMenu.accessibilityLabel(
      sessionType: .shortBreak, state: .paused, secondsRemaining: 90,
      isBreakPostponed: false, isWaitingToContinue: false)
    XCTAssertTrue(paused.hasPrefix("TimeMate, Short Break, paused, "), paused)

    let idle = StatusItemMenu.accessibilityLabel(
      sessionType: .focus, state: .idle, secondsRemaining: 25 * 60,
      isBreakPostponed: false, isWaitingToContinue: false)
    XCTAssertTrue(idle.hasPrefix("TimeMate, Focus, ready, "), idle)

    let postponed = StatusItemMenu.accessibilityLabel(
      sessionType: .longBreak, state: .active, secondsRemaining: 60,
      isBreakPostponed: true, isWaitingToContinue: false)
    XCTAssertTrue(postponed.hasPrefix("TimeMate, Break postponed, "), postponed)

    let finished = StatusItemMenu.accessibilityLabel(
      sessionType: .shortBreak, state: .idle, secondsRemaining: 0,
      isBreakPostponed: false, isWaitingToContinue: true)
    XCTAssertEqual(finished, "TimeMate, Short Break finished")
  }
}
