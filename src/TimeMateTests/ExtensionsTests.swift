//  Created by homielab.com

import XCTest

@testable import TimeMate

final class ExtensionsTests: XCTestCase {
  func testMinuteSecondString() {
    XCTAssertEqual(0.toMinuteSecondString(), "00:00")
    XCTAssertEqual(59.toMinuteSecondString(), "00:59")
    XCTAssertEqual(60.toMinuteSecondString(), "01:00")
    XCTAssertEqual(3599.toMinuteSecondString(), "59:59")
    XCTAssertEqual(10800.toMinuteSecondString(), "180:00")
  }
}
