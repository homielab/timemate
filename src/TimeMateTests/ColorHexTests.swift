//  Created by homielab.com

import AppKit
import XCTest

@testable import TimeMate

final class ColorHexTests: XCTestCase {
  private func components(_ hex: String) -> [CGFloat]? {
    guard let c = NSColor(hex: hex)?.usingColorSpace(.sRGB) else { return nil }
    return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map {
      ($0 * 255).rounded()
    }
  }

  func testSixDigitsWithAndWithoutHash() {
    XCTAssertEqual(components("#FF8000"), [255, 128, 0, 255])
    XCTAssertEqual(components("ff8000"), [255, 128, 0, 255])
  }

  func testThreeDigitsAreDoubled() {
    XCTAssertEqual(components("#f80"), [255, 136, 0, 255])
  }

  func testEightDigitsCarryAlphaLast() {
    XCTAssertEqual(components("#11223380"), [17, 34, 51, 128])
  }

  func testSurroundingWhitespaceIsIgnored() {
    XCTAssertEqual(components("  #000000\n"), [0, 0, 0, 255])
  }

  func testWrongLengthIsRejected() {
    for hex in ["", "#", "#12ab", "#12345", "#1234567", "#123456789"] {
      XCTAssertNil(NSColor(hex: hex), hex)
    }
  }

  func testNonHexCharactersAreRejected() {
    for hex in ["zz", "#gggggg", "12ab zz", "#12 456", "0x1234", "-12345", "#１２３"] {
      XCTAssertNil(NSColor(hex: hex), hex)
    }
  }

  func testRoundTrip() {
    for hex in ["#FF8000", "#0A0B0C", "#11223380", "#FFFFFF", "#000000"] {
      XCTAssertEqual(NSColor(hex: hex)?.toHex(), hex)
    }
  }
}
