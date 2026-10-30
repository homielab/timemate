//  Created by homielab.com

import XCTest

@testable import TimeMate

final class FocusReturnTests: XCTestCase {
  func testReactivatesThePreviousAppWhileTimeMateIsInFront() {
    XCTAssertEqual(FocusReturn.appToReactivate(previous: 10, frontmost: 1, ownPID: 1), 10)
  }

  func testLeavesTheAppTheUserSwitchedTo() {
    XCTAssertNil(FocusReturn.appToReactivate(previous: 10, frontmost: 20, ownPID: 1))
  }

  func testNeverReactivatesItselfOrNothing() {
    XCTAssertNil(FocusReturn.appToReactivate(previous: 1, frontmost: 1, ownPID: 1))
    XCTAssertNil(FocusReturn.appToReactivate(previous: nil, frontmost: 1, ownPID: 1))
  }

  func testSettingsHeightKeepsThePopoverOnA900PointScreen() {
    // 13-inch 1440×900: visible frame ~875 pt under the menu bar.
    let height = PopoverLayout.settingsHeight(visibleHeight: 875, topHeight: 400)
    XCTAssertEqual(height, 435)
    XCTAssertLessThanOrEqual(height + 400 + PopoverLayout.screenMargin, 875)
  }

  func testSettingsHeightStaysAt450OnTallScreens() {
    XCTAssertEqual(PopoverLayout.settingsHeight(visibleHeight: 1400, topHeight: 400), 450)
    XCTAssertEqual(PopoverLayout.settingsHeight(visibleHeight: nil, topHeight: 400), 450)
  }

  func testSettingsHeightHasAFloor() {
    XCTAssertEqual(
      PopoverLayout.settingsHeight(visibleHeight: 300, topHeight: 400),
      PopoverLayout.settingsMinHeight)
  }
}
