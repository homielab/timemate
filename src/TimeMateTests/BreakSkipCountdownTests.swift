//  Created by homielab.com

import XCTest

@testable import TimeMate

final class BreakSkipCountdownTests: XCTestCase {
  func testZeroDelayCanSkipImmediately() {
    let countdown = BreakSkipCountdown(skipDelay: 0)
    XCTAssertEqual(countdown.remainingSeconds, 0)
    XCTAssertTrue(countdown.canSkip)
  }

  func testCountdownTicksUntilCanSkip() {
    var countdown = BreakSkipCountdown(skipDelay: 5)
    XCTAssertEqual(countdown.remainingSeconds, 5)
    XCTAssertFalse(countdown.canSkip)

    XCTAssertFalse(countdown.tick())
    XCTAssertEqual(countdown.remainingSeconds, 4)
    XCTAssertFalse(countdown.canSkip)

    XCTAssertFalse(countdown.tick())
    XCTAssertEqual(countdown.remainingSeconds, 3)

    XCTAssertFalse(countdown.tick())
    XCTAssertEqual(countdown.remainingSeconds, 2)

    XCTAssertFalse(countdown.tick())
    XCTAssertEqual(countdown.remainingSeconds, 1)
    XCTAssertFalse(countdown.canSkip)

    // Last tick hits 0 and enables skip
    XCTAssertTrue(countdown.tick())
    XCTAssertEqual(countdown.remainingSeconds, 0)
    XCTAssertTrue(countdown.canSkip)

    // Further ticks do nothing and return false
    XCTAssertFalse(countdown.tick())
    XCTAssertEqual(countdown.remainingSeconds, 0)
    XCTAssertTrue(countdown.canSkip)
  }

  func testResetWithNewDelay() {
    var countdown = BreakSkipCountdown(skipDelay: 2)
    _ = countdown.tick()
    _ = countdown.tick()
    XCTAssertTrue(countdown.canSkip)

    countdown.reset(skipDelay: 10)
    XCTAssertEqual(countdown.remainingSeconds, 10)
    XCTAssertFalse(countdown.canSkip)
  }

  func testStoredDelayClamping() {
    let negative = BreakSkipCountdown(skipDelay: -5)
    XCTAssertEqual(negative.remainingSeconds, 0)
    XCTAssertTrue(negative.canSkip)

    let excessive = BreakSkipCountdown(skipDelay: 999)
    XCTAssertEqual(excessive.remainingSeconds, BreakOverlayAccessibility.skipDelayRange.upperBound)
  }
}
