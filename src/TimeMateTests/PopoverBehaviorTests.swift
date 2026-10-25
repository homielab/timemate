//  Created by homielab.com

import AppKit
import XCTest

@testable import TimeMate

final class PopoverBehaviorTests: XCTestCase {
  func testKeepWindowOnTopKeepsPopoverOpenOnOutsideClicks() {
    XCTAssertEqual(AppDelegate.popoverBehavior(alwaysVisible: true), .applicationDefined)
  }

  func testPopoverClosesOnOutsideClicksByDefault() {
    XCTAssertEqual(AppDelegate.popoverBehavior(alwaysVisible: false), .transient)
  }
}
