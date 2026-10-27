//  Created by homielab.com

import XCTest

@testable import TimeMate

final class TickModeTests: XCTestCase {
  private func mode(
    popover: Bool = false, menuBarTime: MenuBarTimeStyle = .iconOnly, overlay: Bool = false,
    voiceOver: Bool = false
  ) -> TickMode {
    TickMode.mode(
      popoverOpen: popover, menuBarStyle: menuBarTime, breakOverlayShown: overlay,
      voiceOverRunning: voiceOver)
  }

  func testNothingShowingTheCountdownTicksOnlyAtTheEnd() {
    XCTAssertEqual(mode(), .atEnd)
  }

  func testTimeInTheMenuBarTicksEverySecond() {
    XCTAssertEqual(mode(menuBarTime: .minutesSeconds), .everySecond)
  }

  func testMinutesOnlyTicksOncePerMinuteWhenNothingElseShowsSeconds() {
    XCTAssertEqual(mode(menuBarTime: .minutesOnly), .everyMinute)
  }

  func testMinutesOnlyTicksEverySecondWhileSecondsAreVisible() {
    XCTAssertEqual(mode(popover: true, menuBarTime: .minutesOnly), .everySecond)
    XCTAssertEqual(mode(menuBarTime: .minutesOnly, overlay: true), .everySecond)
    // VoiceOver reads the full minutes and seconds.
    XCTAssertEqual(mode(menuBarTime: .minutesOnly, voiceOver: true), .everySecond)
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
