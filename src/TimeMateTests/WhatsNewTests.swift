import XCTest

/// The App Store "What's New" texts in `docs/whats-new/` must fit the store limit and
/// say the same in both languages.
final class WhatsNewTests: XCTestCase {
  private static let storeLimit = 4000

  private func text(_ localization: String) throws -> String {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("docs/whats-new/\(localization).txt")
    return try String(contentsOf: file, encoding: .utf8)
  }

  private func bulletCount(_ text: String) -> Int {
    text.split(separator: "\n").filter { $0.hasPrefix("•") }.count
  }

  func testFitsTheAppStoreLimit() throws {
    for localization in ["en", "vi"] {
      let count = try text(localization).count
      XCTAssertLessThanOrEqual(count, Self.storeLimit, localization)
    }
  }

  func testBothLanguagesHaveTheSameBullets() throws {
    let english = try text("en")
    XCTAssertGreaterThan(bulletCount(english), 0)
    XCTAssertEqual(bulletCount(english), bulletCount(try text("vi")))
  }
}
