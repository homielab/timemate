//  Created by homielab.com

import XCTest

@testable import TimeMate

final class TickModeTests: XCTestCase {
  private func mode(
    popover: Bool = false, menuBarTime: Bool = false, overlay: Bool = false,
    voiceOver: Bool = false
  ) -> TickMode {
    TickMode.mode(
      popoverOpen: popover, menuBarShowsTime: menuBarTime, breakOverlayShown: overlay,
      voiceOverRunning: voiceOver)
  }

  func testNothingShowingTheCountdownTicksOnlyAtTheEnd() {
    XCTAssertEqual(mode(), .atEnd)
  }

  func testTimeInTheMenuBarTicksEverySecond() {
    XCTAssertEqual(mode(menuBarTime: true), .everySecond)
  }

  func testOpenPopoverTicksEverySecondWithTheMenuBarTimeHidden() {
    XCTAssertEqual(mode(popover: true), .everySecond)
  }

  func testBreakScreenAndVoiceOverTickEverySecond() {
    XCTAssertEqual(mode(overlay: true), .everySecond)
    XCTAssertEqual(mode(voiceOver: true), .everySecond)
  }

  func testTicksMayRunLateByAFifthOfASecond() {
    XCTAssertEqual(TickMode.tolerance, 0.2)
  }
}
