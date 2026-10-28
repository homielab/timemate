//  Created by homielab.com

import XCTest

@testable import TimeMate

final class StatusItemPolicyTests: XCTestCase {
  func testVoiceOverOnMakesTheLabelFollowTheTimer() {
    XCTAssertEqual(
      StatusItemPolicy.label(voiceOverEnabled: true, appName: "TimeMate"), .followsTimer)
  }

  func testVoiceOverOffKeepsTheAppName() {
    XCTAssertEqual(
      StatusItemPolicy.label(voiceOverEnabled: false, appName: "TimeMate"), .fixed("TimeMate"))
    XCTAssertEqual(
      StatusItemPolicy.label(voiceOverEnabled: false, appName: ""), .fixed(""))
  }

  func testLabelUpdateTable() {
    let cases: [(current: String?, new: String, expected: String?, line: UInt)] = [
      // Same text: nothing to post.
      (
        "TimeMate, Focus, 12 minutes remaining", "TimeMate, Focus, 12 minutes remaining", nil,
        #line
      ),
      // The time moved on.
      (
        "TimeMate, Focus, 12 minutes remaining", "TimeMate, Focus, 11 minutes remaining",
        "TimeMate, Focus, 11 minutes remaining", #line
      ),
      // No label yet.
      (nil, "TimeMate, Ready", "TimeMate, Ready", #line),
      // Switching from the app name to the timer sentence.
      ("TimeMate", "TimeMate, Paused", "TimeMate, Paused", #line),
      // An empty label is still a change.
      ("TimeMate", "", "", #line),
      ("", "", nil, #line),
      // Case differences count as a change.
      ("timemate", "TimeMate", "TimeMate", #line),
    ]
    for item in cases {
      XCTAssertEqual(
        StatusItemPolicy.labelUpdate(current: item.current, new: item.new), item.expected,
        line: item.line)
    }
  }
}
