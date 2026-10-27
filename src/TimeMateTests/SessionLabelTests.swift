//  Created by homielab.com

import XCTest

@testable import TimeMate

final class SessionLabelTests: XCTestCase {
  func testEmptyOrBlankIsNil() {
    XCTAssertNil(SessionLabel.normalized(nil))
    XCTAssertNil(SessionLabel.normalized(""))
    XCTAssertNil(SessionLabel.normalized("   \n\t "))
  }

  func testTrimsAndKeepsOneLine() {
    XCTAssertEqual(SessionLabel.normalized("  Write report "), "Write report")
    XCTAssertEqual(SessionLabel.normalized("Write\nreport"), "Write report")
  }

  func testCutsLongLabels() {
    let long = String(repeating: "a", count: SessionLabel.maxLength + 20)
    XCTAssertEqual(SessionLabel.normalized(long)?.count, SessionLabel.maxLength)
  }
}
