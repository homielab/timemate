//  Created by homielab.com

import XCTest

@testable import TimeMate

final class SessionDurationTests: XCTestCase {
  func testAcceptsWholeMinutesInRange() {
    XCTAssertEqual(SessionDuration.minutes(from: "1"), 1)
    XCTAssertEqual(SessionDuration.minutes(from: "50"), 50)
    XCTAssertEqual(SessionDuration.minutes(from: "90"), 90)
    XCTAssertEqual(SessionDuration.minutes(from: "180"), 180)
  }

  func testIgnoresSurroundingWhitespace() {
    XCTAssertEqual(SessionDuration.minutes(from: " 90 \n"), 90)
  }

  func testRejectsValuesOutsideRange() {
    XCTAssertNil(SessionDuration.minutes(from: "0"))
    XCTAssertNil(SessionDuration.minutes(from: "181"))
    XCTAssertNil(SessionDuration.minutes(from: "-5"))
  }

  func testRejectsNonNumbers() {
    XCTAssertNil(SessionDuration.minutes(from: ""))
    XCTAssertNil(SessionDuration.minutes(from: "abc"))
    XCTAssertNil(SessionDuration.minutes(from: "12.5"))
    XCTAssertNil(SessionDuration.minutes(from: "9 0"))
  }

  func testStoredValuesAreAtLeastOneMinute() {
    XCTAssertEqual(SessionDuration.sanitized(0), 1)
    XCTAssertEqual(SessionDuration.sanitized(-3), 1)
    XCTAssertEqual(SessionDuration.sanitized(90), 90)
  }
}

final class OverlayVisibilityGenerationTests: XCTestCase {
  func testFadeOutClosesWhenNothingHappensMeanwhile() {
    var generation = OverlayVisibilityGeneration()
    let token = generation.beginHide()
    XCTAssertTrue(generation.shouldClose(token))
    XCTAssertFalse(generation.isClosePending)
  }

  func testShowingDuringFadeOutCancelsTheClose() {
    var generation = OverlayVisibilityGeneration()
    let token = generation.beginHide()
    XCTAssertTrue(generation.beginShow(), "show must fade the windows back in")
    XCTAssertFalse(generation.shouldClose(token), "the overlay must stay visible")
  }

  func testShowWithoutFadeOutReportsNothingCancelled() {
    var generation = OverlayVisibilityGeneration()
    XCTAssertFalse(generation.beginShow())
  }

  func testOnlyTheLatestFadeOutMayClose() {
    var generation = OverlayVisibilityGeneration()
    let first = generation.beginHide()
    let second = generation.beginHide()
    XCTAssertFalse(generation.shouldClose(first))
    XCTAssertTrue(generation.shouldClose(second))
  }

  func testHideShowHideClosesOnlyForTheLastHide() {
    var generation = OverlayVisibilityGeneration()
    let first = generation.beginHide()
    _ = generation.beginShow()
    let second = generation.beginHide()
    XCTAssertFalse(generation.shouldClose(first))
    XCTAssertTrue(generation.shouldClose(second))
    XCTAssertFalse(generation.shouldClose(second), "a close happens once")
  }
}
