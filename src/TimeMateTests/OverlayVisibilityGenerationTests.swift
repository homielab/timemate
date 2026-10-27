//  Created by homielab.com

import XCTest

@testable import TimeMate

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
