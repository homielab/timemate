//  Created by homielab.com

import XCTest

@testable import TimeMate

final class OverlayPolicyTests: XCTestCase {
  private func presentation(
    shouldShow: Bool = true, skip: Bool = true, fullscreen: Bool, visible: Bool = false
  ) -> OverlayPolicy.Presentation {
    OverlayPolicy.presentation(
      shouldShow: shouldShow, skipFullscreen: skip, isFrontmostFullscreen: fullscreen,
      isVisible: visible)
  }

  func testShowsWhenNothingIsFullscreen() {
    XCTAssertEqual(presentation(fullscreen: false), .show)
  }

  func testWaitsWhileFrontmostAppIsFullscreen() {
    XCTAssertEqual(presentation(fullscreen: true), .waitForWindowedApp)
  }

  func testShowsOverFullscreenWhenOptionIsOff() {
    XCTAssertEqual(presentation(skip: false, fullscreen: true), .show)
  }

  func testHidesWhenBreakIsNotDueEvenIfFullscreen() {
    XCTAssertEqual(presentation(shouldShow: false, fullscreen: true), .hide)
    XCTAssertEqual(presentation(shouldShow: false, fullscreen: false), .hide)
  }

  func testVisibleOverlayStaysWhenFullscreenAppAppears() {
    XCTAssertEqual(presentation(fullscreen: true, visible: true), .show)
  }

  func testFullscreenDetection() {
    let screen = CGSize(width: 1440, height: 900)
    XCTAssertTrue(
      OverlayPolicy.isFullscreen(
        windowSizes: [CGSize(width: 1440, height: 900)], screenSizes: [screen]))
    XCTAssertFalse(
      OverlayPolicy.isFullscreen(
        windowSizes: [CGSize(width: 1440, height: 875)], screenSizes: [screen]))
    XCTAssertFalse(OverlayPolicy.isFullscreen(windowSizes: [], screenSizes: [screen]))
    XCTAssertTrue(
      OverlayPolicy.isFullscreen(
        windowSizes: [CGSize(width: 100, height: 50), CGSize(width: 1920, height: 1080)],
        screenSizes: [screen, CGSize(width: 1920, height: 1080)]))
  }

  func testClockRunsOnlyBetweenStartAndStop() {
    let clock = OverlayClock()
    XCTAssertFalse(clock.isRunning)
    clock.start()
    XCTAssertTrue(clock.isRunning)
    clock.stop()
    XCTAssertFalse(clock.isRunning)
  }
}
