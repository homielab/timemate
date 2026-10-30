//  Created by homielab.com

import XCTest

@testable import TimeMate

/// Shortcuts looks up every title, description, summary and parameter prompt of the App
/// Intents, and the names of what they return, in `Localizable.strings`. A key missing from
/// both tables passes the en/vi parity check but shows English in Vietnamese Shortcuts, so
/// read the literals from `Intents.swift` and `IntentEntities.swift`.
final class IntentStringsTests: XCTestCase {
  private var sources: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("TimeMate")
  }

  private func strings(_ localization: String) throws -> [String: String] {
    let bundle = Bundle(for: PomodoroTimer.self)
    let path = try XCTUnwrap(
      bundle.path(
        forResource: "Localizable", ofType: "strings", inDirectory: nil,
        forLocalization: localization))
    return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
  }

  func testEveryIntentStringIsInBothTables() throws {
    let source = try ["Intents.swift", "IntentEntities.swift"].map {
      try String(contentsOf: sources.appendingPathComponent($0), encoding: .utf8)
    }.joined(separator: "\n")
    let keys = Self.intentStringKeys(inSwiftSource: source)
    XCTAssertTrue(keys.contains("Start Focus"), "parser found no intent titles")
    XCTAssertTrue(keys.contains("Minutes Left"), "parser found no entity properties")
    for localization in ["en", "vi"] {
      let table = try strings(localization)
      XCTAssertEqual(
        keys.filter { table[$0] == nil }, [], "missing in \(localization).lproj/Localizable.strings"
      )
    }
  }

  func testIntentStringParsing() {
    let source = #"""
      static var title: LocalizedStringResource = "Go"
      static var description = IntentDescription(
        "Does \"it\".")
      @Parameter(title: "Label", requestValueDialog: "Which one?")
      @Parameter(title: "Minutes", default: 5)
      Summary("Start on \(\.$label)")
      // IntentDialog(stringLiteral: text) is built at run time
      static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Kind")
      .idle: DisplayRepresentation(title: "Idle"),
      @Property(title: "Left") var left: Int
      DisplayRepresentation(title: LocalizedStringResource(stringLiteral: text))
      """#
    XCTAssertEqual(
      Self.intentStringKeys(inSwiftSource: source),
      [
        "Does \"it\".", "Go", "Idle", "Kind", "Label", "Left", "Minutes", "Start on ${label}",
        "Which one?",
      ])
  }

  /// The literal after each place App Intents localizes a string, with `\(\.$name)`
  /// written as Shortcuts' key placeholder `${name}`.
  static func intentStringKeys(inSwiftSource source: String) -> [String] {
    let literal = #""((?:[^"\\]|\\.)*)""#
    let prefixes = [
      #"title:\s*LocalizedStringResource\s*=\s*"#, #"IntentDescription\(\s*"#,
      #"Summary\(\s*"#, #"Parameter\(\s*title:\s*"#, #"requestValueDialog:\s*"#,
      #"Property\(\s*title:\s*"#, #"TypeDisplayRepresentation\(\s*name:\s*"#,
      #"DisplayRepresentation\(\s*title:\s*"#,
    ]
    var keys = Set<String>()
    for prefix in prefixes {
      let regex = try! NSRegularExpression(pattern: prefix + literal)
      let range = NSRange(source.startIndex..., in: source)
      for match in regex.matches(in: source, range: range) {
        guard let value = Range(match.range(at: 1), in: source) else { continue }
        keys.insert(unescape(String(source[value])))
      }
    }
    return keys.sorted()
  }

  private static func unescape(_ literal: String) -> String {
    let placeholder = try! NSRegularExpression(pattern: #"\\\(\\\.\$(\w+)\)"#)
    let text = placeholder.stringByReplacingMatches(
      in: literal, range: NSRange(literal.startIndex..., in: literal), withTemplate: "\\${$1}")
    return text.replacingOccurrences(of: #"\""#, with: "\"")
      .replacingOccurrences(of: #"\\"#, with: "\\")
  }
}
