//  Created by homielab.com

import XCTest

@testable import TimeMate

final class BreakOverlayAccessibilityTests: XCTestCase {
  func testAnnouncesBreakLengthInMinutes() {
    XCTAssertEqual(
      BreakOverlayAccessibility.announcement(secondsRemaining: 300), "Break started, 5 minutes")
  }

  func testAnnouncementRoundsUpAndUsesSingular() {
    XCTAssertEqual(
      BreakOverlayAccessibility.announcement(secondsRemaining: 299), "Break started, 5 minutes")
    XCTAssertEqual(
      BreakOverlayAccessibility.announcement(secondsRemaining: 60), "Break started, 1 minute")
    XCTAssertEqual(
      BreakOverlayAccessibility.announcement(secondsRemaining: 5), "Break started, 1 minute")
  }

  func testCountdownValueIsSpelledOut() {
    let value = BreakOverlayAccessibility.countdownValue(secondsRemaining: 270)
    XCTAssertFalse(value.contains(":"), value)
    XCTAssertTrue(value.contains("4"), value)
    XCTAssertTrue(value.contains("30"), value)
  }

  func testPrimaryScreenIsTheMainScreen() {
    let left = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let right = CGRect(x: 1440, y: 0, width: 2560, height: 1440)
    XCTAssertEqual(
      BreakOverlayAccessibility.primaryScreenIndex(screens: [left, right], main: right), 1)
  }

  func testPrimaryScreenFallsBackToFirst() {
    let left = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let other = CGRect(x: -100, y: 0, width: 10, height: 10)
    XCTAssertEqual(
      BreakOverlayAccessibility.primaryScreenIndex(screens: [left], main: nil), 0)
    XCTAssertEqual(
      BreakOverlayAccessibility.primaryScreenIndex(screens: [left], main: other), 0)
  }

  func testReduceMotionSkipsTheFade() {
    XCTAssertNil(BreakOverlayAccessibility.fadeDuration(reduceMotion: true))
    XCTAssertEqual(BreakOverlayAccessibility.fadeDuration(reduceMotion: false), 1.5)
  }

  func testSkipDelayDefaultsToFiveAndIsClamped() {
    XCTAssertEqual(BreakOverlayAccessibility.skipDelay(stored: nil), 5)
    XCTAssertEqual(BreakOverlayAccessibility.skipDelay(stored: 0), 0)
    XCTAssertEqual(BreakOverlayAccessibility.skipDelay(stored: 12), 12)
    XCTAssertEqual(BreakOverlayAccessibility.skipDelay(stored: -3), 0)
    XCTAssertEqual(BreakOverlayAccessibility.skipDelay(stored: 99), 30)
  }

  func testPostponeLabelsAreSpelledOut() {
    XCTAssertEqual(
      BreakOverlayAccessibility.postponeLabel(minutes: 1), "Postpone break by 1 minute")
    XCTAssertEqual(
      BreakOverlayAccessibility.postponeLabel(minutes: 3), "Postpone break by 3 minutes")
    XCTAssertEqual(BreakOverlayAccessibility.postponeOptions, [1, 3, 5])
  }
}
