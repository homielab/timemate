//  Created by homielab.com

import XCTest

@testable import TimeMate

final class AutoStartTests: XCTestCase {
  private static let suiteName = "AutoStartTests"
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: Self.suiteName)
    defaults.removePersistentDomain(forName: Self.suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  func testDecisionTable() {
    let cases: [(breaks: Bool, focus: Bool, next: SessionType, start: Bool)] = [
      (true, true, .shortBreak, true), (true, true, .longBreak, true), (true, true, .focus, true),
      (true, false, .shortBreak, true), (true, false, .longBreak, true),
      (true, false, .focus, false),
      (false, true, .shortBreak, false), (false, true, .longBreak, false),
      (false, true, .focus, true),
      (false, false, .shortBreak, false), (false, false, .longBreak, false),
      (false, false, .focus, false),
    ]
    for c in cases {
      XCTAssertEqual(
        AutoStart(breaks: c.breaks, focus: c.focus).shouldStart(next: c.next), c.start,
        "breaks \(c.breaks), focus \(c.focus), next \(c.next)")
    }
  }

  func testNothingSetKeepsTheOldDefault() {
    XCTAssertEqual(AutoStart(defaults: defaults), .default)
  }

  func testOldSwitchOffTurnsBothOff() {
    defaults.set(false, forKey: SettingsKey.autoStartNextSession)
    XCTAssertEqual(AutoStart(defaults: defaults), AutoStart(breaks: false, focus: false))
  }

  func testOldSwitchOnTurnsBothOn() {
    defaults.set(true, forKey: SettingsKey.autoStartNextSession)
    XCTAssertEqual(AutoStart(defaults: defaults), AutoStart(breaks: true, focus: true))
  }

  func testNewSwitchWinsOverTheOldOne() {
    defaults.set(false, forKey: SettingsKey.autoStartNextSession)
    defaults.set(true, forKey: SettingsKey.autoStartBreaks)
    XCTAssertEqual(AutoStart(defaults: defaults), AutoStart(breaks: true, focus: false))
    defaults.set(true, forKey: SettingsKey.autoStartNextSession)
    defaults.set(false, forKey: SettingsKey.autoStartFocus)
    XCTAssertEqual(AutoStart(defaults: defaults), AutoStart(breaks: true, focus: false))
  }
}
