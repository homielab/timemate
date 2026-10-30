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

  func testAssignmentPrefersTheStartLabelElseTheField() {
    XCTAssertEqual(LabelAssignment.label(started: "A", field: "B"), "A")
    XCTAssertEqual(LabelAssignment.label(started: "", field: " B "), "B")
    XCTAssertEqual(LabelAssignment.label(started: nil, field: "B"), "B")
    XCTAssertNil(LabelAssignment.label(started: "", field: "  "))
  }

  func testCaptionFollowsTheSession() {
    XCTAssertEqual(LabelAssignment.caption(inFocusSession: false, started: "A"), .idle)
    XCTAssertEqual(LabelAssignment.caption(inFocusSession: true, started: nil), .idle)
    XCTAssertEqual(LabelAssignment.caption(inFocusSession: true, started: ""), .currentSession)
    XCTAssertEqual(LabelAssignment.caption(inFocusSession: true, started: "A"), .nextSession)
  }

  func testCaptionTextsAreLocalized() throws {
    let expected: [String: (String, String)] = [
      "Saved with each focus session you complete": (
        "Saved with each focus session you complete", "Lưu cùng mỗi phiên tập trung bạn hoàn thành"
      ),
      "Saved with this focus session": (
        "Saved with this focus session", "Lưu cùng phiên tập trung này"
      ),
      "Applies from the next session": ("Applies from the next session", "Áp dụng từ phiên sau"),
    ]
    let app = Bundle(for: PomodoroTimer.self)
    for (key, (en, vi)) in expected {
      for (lang, value) in [("en", en), ("vi", vi)] {
        let path = try XCTUnwrap(app.path(forResource: lang, ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(bundle.localizedString(forKey: key, value: nil, table: nil), value)
      }
    }
    let captions: [LabelAssignment.Caption] = [.idle, .currentSession, .nextSession]
    XCTAssertEqual(Set(captions.map(\.text)).count, 3)
  }

  func testLabelFieldHintIsTheCaptionSoVoiceOverReadsIt() {
    for caption in [LabelAssignment.Caption.idle, .currentSession, .nextSession] {
      XCTAssertEqual(SessionLabelField.hint(for: caption), caption.text)
    }
  }
}
