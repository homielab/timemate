//  Created by homielab.com

import XCTest

@testable import TimeMate

final class BreakOverlayMotionTests: XCTestCase {
  func testCatPlaysOnlyDuringTheBreakWithoutReduceMotion() {
    XCTAssertTrue(BreakOverlayMotion.animatesCat(reduceMotion: false, isWaitingToContinue: false))
    XCTAssertFalse(BreakOverlayMotion.animatesCat(reduceMotion: false, isWaitingToContinue: true))
    XCTAssertFalse(BreakOverlayMotion.animatesCat(reduceMotion: true, isWaitingToContinue: false))
    XCTAssertFalse(BreakOverlayMotion.animatesCat(reduceMotion: true, isWaitingToContinue: true))
  }

  func testClockTicksOnceAMinuteWhileWaitingToContinue() {
    XCTAssertEqual(BreakOverlayMotion.clockInterval(isWaitingToContinue: true), 60)
    XCTAssertEqual(BreakOverlayMotion.clockInterval(isWaitingToContinue: false), 1)
  }

  func testNextTickLandsOnTheNextWholeInterval() {
    let start = Date(timeIntervalSinceReferenceDate: 600)
    XCTAssertEqual(
      BreakOverlayMotion.nextTick(after: start.addingTimeInterval(12.5), interval: 60),
      Date(timeIntervalSinceReferenceDate: 660))
    XCTAssertEqual(
      BreakOverlayMotion.nextTick(after: start, interval: 60),
      Date(timeIntervalSinceReferenceDate: 660), "a tick exactly on the minute waits for the next")
    XCTAssertEqual(
      BreakOverlayMotion.nextTick(after: start.addingTimeInterval(0.3), interval: 1),
      Date(timeIntervalSinceReferenceDate: 601))
  }
}
