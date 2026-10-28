//  Created by homielab.com

import XCTest

@testable import TimeMate

final class SessionDurationTests: XCTestCase {
  func testAcceptsWholeMinutesInRange() {
    XCTAssertEqual(SessionDuration.minutes(from: "1"), 1)
    XCTAssertEqual(SessionDuration.minutes(from: "50"), 50)
    XCTAssertEqual(SessionDuration.minutes(from: "90"), 90)
    XCTAssertEqual(SessionDuration.minutes(from: "180"), 180)
  }

  func testIgnoresSurroundingWhitespace() {
    XCTAssertEqual(SessionDuration.minutes(from: " 90 \n"), 90)
  }

  func testRejectsValuesOutsideRange() {
    XCTAssertNil(SessionDuration.minutes(from: "0"))
    XCTAssertNil(SessionDuration.minutes(from: "181"))
    XCTAssertNil(SessionDuration.minutes(from: "-5"))
  }

  func testRejectsNonNumbers() {
    XCTAssertNil(SessionDuration.minutes(from: ""))
    XCTAssertNil(SessionDuration.minutes(from: "abc"))
    XCTAssertNil(SessionDuration.minutes(from: "12.5"))
    XCTAssertNil(SessionDuration.minutes(from: "9 0"))
  }

  func testStoredValuesAreAtLeastOneMinute() {
    XCTAssertEqual(SessionDuration.sanitized(0), 1)
    XCTAssertEqual(SessionDuration.sanitized(-3), 1)
    XCTAssertEqual(SessionDuration.sanitized(90), 90)
  }

  func testValidationHint() {
    XCTAssertEqual(SessionDuration.validationHint(for: ""), .empty)
    XCTAssertEqual(SessionDuration.validationHint(for: "  "), .empty)
    XCTAssertEqual(SessionDuration.validationHint(for: "0"), .tooShort)
    XCTAssertEqual(SessionDuration.validationHint(for: "-5"), .tooShort)
    XCTAssertEqual(SessionDuration.validationHint(for: "181"), .tooLong)
    XCTAssertEqual(SessionDuration.validationHint(for: "abc"), .notANumber)
    XCTAssertEqual(SessionDuration.validationHint(for: "12.5"), .notANumber)
    XCTAssertNil(SessionDuration.validationHint(for: "45"))
    XCTAssertNil(SessionDuration.validationHint(for: " 180 "))
  }

  func testValidationHintsAreLocalized() throws {
    let bundle = Bundle(for: PomodoroTimer.self)
    for lang in ["en", "vi"] {
      let path = try XCTUnwrap(bundle.path(forResource: lang, ofType: "lproj"))
      let langBundle = try XCTUnwrap(Bundle(path: path))
      for problem in [
        SessionDuration.Problem.empty, .notANumber, .tooShort, .tooLong,
      ] {
        let text = langBundle.localizedString(forKey: problem.rawValue, value: "\u{0}", table: nil)
        XCTAssertNotEqual(text, "\u{0}", "\(lang) misses \(problem.rawValue)")
      }
    }
  }
}
