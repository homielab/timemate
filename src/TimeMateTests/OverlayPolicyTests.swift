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

  func testCallsAreIgnoredWhileWaitDuringCallsIsOff() {
    XCTAssertEqual(
      OverlayPolicy.presentation(
        shouldShow: true, skipFullscreen: true, isFrontmostFullscreen: false,
        waitDuringCalls: false, otherAppKeepsDisplayAwake: true),
      .show)
  }

  func testWaitsDuringACallWhenWaitDuringCallsIsOn() {
    XCTAssertEqual(
      OverlayPolicy.presentation(
        shouldShow: true, skipFullscreen: false, isFrontmostFullscreen: false,
        waitDuringCalls: true, otherAppKeepsDisplayAwake: true),
      .waitForWindowedApp)
  }

  func testShowsWithoutACallWhenWaitDuringCallsIsOn() {
    XCTAssertEqual(
      OverlayPolicy.presentation(
        shouldShow: true, skipFullscreen: true, isFrontmostFullscreen: false,
        waitDuringCalls: true, otherAppKeepsDisplayAwake: false),
      .show)
  }

  func testCallNeitherShowsADueBreakScreenNorHidesAVisibleOne() {
    XCTAssertEqual(
      OverlayPolicy.presentation(
        shouldShow: false, skipFullscreen: false, isFrontmostFullscreen: false,
        waitDuringCalls: true, otherAppKeepsDisplayAwake: true),
      .hide)
    XCTAssertEqual(
      OverlayPolicy.presentation(
        shouldShow: true, skipFullscreen: false, isFrontmostFullscreen: false,
        waitDuringCalls: true, otherAppKeepsDisplayAwake: true, isVisible: true),
      .show)
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
    clock.start(interval: 60)
    XCTAssertEqual(clock.interval, 60)
    clock.stop()
  }

  func testBreakScreenCanShowNeedsTheOverlayAndNoHoldingFullScreenApp() {
    func canShow(enabled: Bool, skip: Bool, fullscreen: Bool) -> Bool {
      OverlayPolicy.breakScreenCanShow(
        settings: OverlaySettings(enabled: enabled, skipFullscreen: skip),
        isFrontmostFullscreen: { fullscreen }, otherAppKeepsDisplayAwake: { true })
    }
    XCTAssertTrue(canShow(enabled: true, skip: true, fullscreen: false))
    XCTAssertTrue(canShow(enabled: true, skip: false, fullscreen: true))
    XCTAssertFalse(canShow(enabled: true, skip: true, fullscreen: true))
    XCTAssertFalse(canShow(enabled: false, skip: false, fullscreen: false))
  }

  func testBreakScreenCanShowWaitsForACallOnlyWithTheSetting() {
    var probed = false
    func canShow(wait: Bool, awake: Bool) -> Bool {
      OverlayPolicy.breakScreenCanShow(
        settings: OverlaySettings(enabled: true, skipFullscreen: false, waitDuringCalls: wait),
        isFrontmostFullscreen: { false },
        otherAppKeepsDisplayAwake: {
          probed = true
          return awake
        })
    }
    XCTAssertTrue(canShow(wait: false, awake: true))
    XCTAssertFalse(probed, "Setting off: the assertions are not read")
    XCTAssertFalse(canShow(wait: true, awake: true))
    XCTAssertTrue(canShow(wait: true, awake: false))
  }
}
