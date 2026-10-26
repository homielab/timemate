//  Created by homielab.com

import XCTest

@testable import TimeMate

/// Every string the app shows must exist in English and Vietnamese with the same
/// format specifiers, or `String(format:)` reads the wrong arguments.
final class LocalizationParityTests: XCTestCase {
  private func strings(_ table: String, _ localization: String) throws -> [String: String] {
    let bundle = Bundle(for: PomodoroTimer.self)
    let path = try XCTUnwrap(
      bundle.path(
        forResource: table, ofType: "strings", inDirectory: nil, forLocalization: localization),
      "\(localization).lproj/\(table).strings is missing")
    return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
  }

  func testEnglishAndVietnameseHaveTheSameKeys() throws {
    let english = try strings("Localizable", "en")
    let vietnamese = try strings("Localizable", "vi")
    XCTAssertFalse(english.isEmpty)
    XCTAssertEqual(
      Set(english.keys).subtracting(vietnamese.keys).sorted(), [], "missing in vi.lproj")
    XCTAssertEqual(
      Set(vietnamese.keys).subtracting(english.keys).sorted(), [], "missing in en.lproj")
  }

  func testEnglishAndVietnameseUseTheSameFormatSpecifiers() throws {
    let english = try strings("Localizable", "en")
    let vietnamese = try strings("Localizable", "vi")
    for (key, value) in english {
      guard let translation = vietnamese[key] else { continue }
      XCTAssertEqual(
        Self.formatSpecifiers(in: translation), Self.formatSpecifiers(in: value),
        "format specifiers differ for \"\(key)\"")
    }
  }

  func testNoTranslationIsEmpty() throws {
    for localization in ["en", "vi"] {
      let table = try strings("Localizable", localization)
      let empty = table.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }
      XCTAssertEqual(empty.keys.sorted(), [], "empty values in \(localization).lproj")
    }
  }

  func testFormatSpecifierParsing() {
    XCTAssertEqual(Self.formatSpecifiers(in: "Cycle %d / %d"), ["d", "d"])
    XCTAssertEqual(Self.formatSpecifiers(in: "%@ · %lld min · 100%%"), ["@", "lld"])
    XCTAssertEqual(Self.formatSpecifiers(in: "%2$@ then %1$d"), ["d", "@"])
    XCTAssertEqual(Self.formatSpecifiers(in: "%.1f%%"), ["f"])
    XCTAssertEqual(Self.formatSpecifiers(in: "no arguments"), [])
  }

  /// The argument types a format string reads, in argument order (positional
  /// `%2$@` specifiers are put in their argument's place). `%%` is not one.
  static func formatSpecifiers(in format: String) -> [String] {
    // %[position$][flags][width][.precision][length]conversion
    let pattern =
      #"%(?:(\d+)\$)?[-+ #0']*\d*(?:\.\d+)?"# + #"(hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfFeEgGaAcCsSp%])"#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(format.startIndex..., in: format)
    var found: [(position: Int, type: String)] = []
    for match in regex.matches(in: format, range: range) {
      guard let conversion = Range(match.range(at: 3), in: format),
        format[conversion] != "%"
      else { continue }
      let length = Range(match.range(at: 2), in: format).map { String(format[$0]) } ?? ""
      let position =
        Range(match.range(at: 1), in: format).flatMap { Int(format[$0]) } ?? found.count + 1
      found.append((position, length + format[conversion]))
    }
    return found.sorted { $0.position < $1.position }.map(\.type)
  }
}
