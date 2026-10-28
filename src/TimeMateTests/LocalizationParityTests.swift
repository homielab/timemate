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

  /// `NSDictionary` keeps the last of two equal keys, so a duplicate would hide which
  /// translation wins: read the raw file and count every `"key" =` line.
  func testNoKeyIsDeclaredTwice() throws {
    // The built bundle holds a compiled plist, so read the sources next to the tests.
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("TimeMate")
    for localization in ["en", "vi"] {
      let file = sources.appendingPathComponent("\(localization).lproj/Localizable.strings")
      let text = try String(contentsOf: file, encoding: .utf8)
      XCTAssertEqual(Self.duplicateKeys(inStringsFile: text), [], "\(localization).lproj")
    }
  }

  func testDuplicateKeyDetection() {
    let text = [
      #""A" = "1";"#, #"// "A" = "in a comment";"#, #""B \"q\"" = "2";"#, #""A" = "3";"#,
    ].joined(separator: "\n")
    XCTAssertEqual(Self.duplicateKeys(inStringsFile: text), ["A"])
    XCTAssertEqual(Self.duplicateKeys(inStringsFile: "\"A\" = \"1\";\n\"B\" = \"2\";"), [])
  }

  /// Keys that start more than one line of a `.strings` file (comment lines are skipped).
  static func duplicateKeys(inStringsFile text: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: #"^\s*"((?:[^"\\]|\\.)*)"\s*="#)
    var seen = Set<String>()
    var duplicates = Set<String>()
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
      let line = String(line)
      guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
        let range = Range(match.range(at: 1), in: line)
      else { continue }
      if !seen.insert(String(line[range])).inserted { duplicates.insert(String(line[range])) }
    }
    return duplicates.sorted()
  }

  func testNoTranslationIsEmpty() throws {
    for localization in ["en", "vi"] {
      let table = try strings("Localizable", localization)
      let empty = table.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }
      XCTAssertEqual(empty.keys.sorted(), [], "empty values in \(localization).lproj")
    }
  }

  /// Strings the code builds by hand (`Text(LocalizedStringKey(tip))`, `rawValue`s,
  /// `NSLocalizedString(key)`) reach no table check on their own: a missing one shows English.
  func testStringsBuiltInCodeExistInBothLanguages() throws {
    let english = try strings("Localizable", "en")
    let vietnamese = try strings("Localizable", "vi")
    let used =
      RelaxationTips.all
      + SessionType.allCases.map(\.rawValue)
      + SessionNotificationAction.allCases.map(\.titleKey)
      + ["Break postponed", BreakOverlayAccessibility.windowTitleKey]
    XCTAssertEqual(Set(used).count, used.count, "duplicate string")
    XCTAssertEqual(used.filter { english[$0] == nil }, [], "missing in en.lproj")
    XCTAssertEqual(used.filter { vietnamese[$0] == nil }, [], "missing in vi.lproj")
  }

  /// Siri phrases have no English table: the phrase itself is the English. Each one
  /// listed in `TimeMateShortcutPhrases` needs a Vietnamese translation, and no stray one.
  func testSiriPhrasesHaveAVietnameseTranslation() throws {
    let vietnamese = try strings("AppShortcuts", "vi")
    let listed = Set(TimeMateShortcutPhrases.keys)
    XCTAssertEqual(listed.count, TimeMateShortcutPhrases.keys.count, "duplicate phrase key")
    XCTAssertEqual(listed.subtracting(vietnamese.keys).sorted(), [], "missing in vi.lproj")
    XCTAssertEqual(
      Set(vietnamese.keys).subtracting(listed).sorted(), [], "not in TimeMateShortcutPhrases")
  }

  // MARK: - Plurals (Localizable.stringsdict)

  private func pluralRules(_ localization: String) throws -> [String: [String: Any]] {
    let bundle = Bundle(for: PomodoroTimer.self)
    let path = try XCTUnwrap(
      bundle.path(
        forResource: "Localizable", ofType: "stringsdict", inDirectory: nil,
        forLocalization: localization),
      "\(localization).lproj/Localizable.stringsdict is missing")
    return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: [String: Any]])
  }

  func testPluralRulesExistInBothLanguages() throws {
    let english = try pluralRules("en")
    let vietnamese = try pluralRules("vi")
    XCTAssertFalse(english.isEmpty)
    XCTAssertEqual(Set(english.keys), Set(vietnamese.keys))
  }

  func testPluralRulesUseTheSameArguments() throws {
    let english = try pluralRules("en")
    let vietnamese = try pluralRules("vi")
    for (key, rule) in english {
      let translation = try XCTUnwrap(vietnamese[key], "missing in vi.lproj: \(key)")
      let format = try XCTUnwrap(rule["NSStringLocalizedFormatKey"] as? String, key)
      let translatedFormat = try XCTUnwrap(
        translation["NSStringLocalizedFormatKey"] as? String, key)
      XCTAssertEqual(
        Self.formatSpecifiers(in: translatedFormat), Self.formatSpecifiers(in: format),
        "format specifiers differ for \"\(key)\"")
      XCTAssertEqual(
        Set(Self.pluralVariables(in: translatedFormat)), Set(Self.pluralVariables(in: format)),
        "plural variables differ for \"\(key)\"")

      for (localization, entry) in [("en", rule), ("vi", translation)] {
        for name in Self.pluralVariables(in: entry["NSStringLocalizedFormatKey"] as? String ?? "") {
          let variable = try XCTUnwrap(
            entry[name] as? [String: String], "\(localization): no rule for \(name) in \(key)")
          XCTAssertEqual(variable["NSStringFormatSpecTypeKey"], "NSStringPluralRuleType")
          let valueType = try XCTUnwrap(variable["NSStringFormatValueTypeKey"], key)
          XCTAssertNotNil(variable["other"], "\(localization): no 'other' form in \(key)")
          for category in ["zero", "one", "two", "few", "many", "other"] {
            guard let form = variable[category] else { continue }
            let specifiers = Self.formatSpecifiers(in: form)
            XCTAssertTrue(
              specifiers.isEmpty || specifiers == [valueType],
              "\(localization): '\(category)' of \(name) in \(key) reads \(specifiers)")
          }
        }
      }
      // Vietnamese has no plural forms: one "other" form says it all.
      for name in Self.pluralVariables(in: translatedFormat) {
        let variable = try XCTUnwrap(translation[name] as? [String: String])
        XCTAssertNil(variable["one"], "vi: unneeded 'one' form of \(name) in \(key)")
      }
    }
  }

  /// Strings with a count read "1 minute", not "1 minutes".
  func testCountedStringsUseTheSingularForOne() throws {
    let bundle = Bundle(for: PomodoroTimer.self)
    let key = "Not saved. Leaving the field keeps %lld minutes."
    for (localization, one, five) in [
      (
        "en", "Not saved. Leaving the field keeps 1 minute.",
        "Not saved. Leaving the field keeps 5 minutes."
      ),
      ("vi", "Chưa lưu. Rời ô sẽ giữ 1 phút.", "Chưa lưu. Rời ô sẽ giữ 5 phút."),
    ] {
      let path = try XCTUnwrap(bundle.path(forResource: localization, ofType: "lproj"))
      let format = try XCTUnwrap(Bundle(path: path)).localizedString(
        forKey: key, value: nil, table: nil)
      let locale = Locale(identifier: localization)
      XCTAssertEqual(String(format: format, locale: locale, 1), one)
      XCTAssertEqual(String(format: format, locale: locale, 5), five)
    }
    // Add Time's summary picks the singular phrase for 1 (Intents.swift).
    let english = try strings("Localizable", "en")
    let vietnamese = try strings("Localizable", "vi")
    XCTAssertEqual(english["Add ${minutes} minute"], "Add ${minutes} minute")
    XCTAssertEqual(vietnamese["Add ${minutes} minute"], "Thêm ${minutes} phút")
  }

  func testPluralKeysAreNotAlsoPlainStrings() throws {
    for localization in ["en", "vi"] {
      let plain = try strings("Localizable", localization)
      let plurals = try pluralRules(localization)
      XCTAssertEqual(
        Set(plain.keys).intersection(plurals.keys).sorted(), [],
        "\(localization): keep each key in one file")
    }
  }

  /// Names of `%#@name@` plural variables in a format.
  static func pluralVariables(in format: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?#@(\w+)@"#)
    let range = NSRange(format.startIndex..., in: format)
    return regex.matches(in: format, range: range).compactMap {
      Range($0.range(at: 1), in: format).map { String(format[$0]) }
    }
  }

  func testPluralVariableParsing() {
    XCTAssertEqual(
      Self.pluralVariables(in: "%1$@: %2$#@pomodoros@, %3$#@minutes@"), ["pomodoros", "minutes"])
    XCTAssertEqual(Self.formatSpecifiers(in: "Today: %1$#@pomodoros@ · %2$lld min"), ["@", "lld"])
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
