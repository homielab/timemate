//  Created by homielab.com

import XCTest

@testable import TimeMate

final class MenuBarTimeStyleTests: XCTestCase {
  private var defaults: UserDefaults!
  private let suite = "MenuBarTimeStyleTests"

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: suite)
    defaults.removePersistentDomain(forName: suite)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suite)
    super.tearDown()
  }

  func testTextForEachStyle() {
    XCTAssertEqual(MenuBarTimeStyle.minutesSeconds.text(seconds: 754), "12:34")
    XCTAssertEqual(MenuBarTimeStyle.minutesOnly.text(seconds: 754), "13m")
    XCTAssertEqual(MenuBarTimeStyle.iconOnly.text(seconds: 754), "")
  }

  func testMinutesRoundUp() {
    XCTAssertEqual(MenuBarTimeStyle.minutes(roundingUp: 1500), 25)
    XCTAssertEqual(MenuBarTimeStyle.minutes(roundingUp: 1499), 25)
    XCTAssertEqual(MenuBarTimeStyle.minutes(roundingUp: 61), 2)
    XCTAssertEqual(MenuBarTimeStyle.minutes(roundingUp: 60), 1)
    XCTAssertEqual(MenuBarTimeStyle.minutes(roundingUp: 1), 1)
    XCTAssertEqual(MenuBarTimeStyle.minutes(roundingUp: 0), 0)
  }

  func testSecondsUntilTheShownMinutesChange() {
    XCTAssertEqual(MenuBarTimeStyle.secondsUntilMinuteChange(remaining: 125), 5, accuracy: 0.001)
    XCTAssertEqual(MenuBarTimeStyle.secondsUntilMinuteChange(remaining: 120), 60, accuracy: 0.001)
    XCTAssertEqual(MenuBarTimeStyle.secondsUntilMinuteChange(remaining: 45), 45, accuracy: 0.001)
    XCTAssertEqual(MenuBarTimeStyle.secondsUntilMinuteChange(remaining: 0), 0)
  }

  func testMigrationFromTheOldSwitch() {
    defaults.set(true, forKey: SettingsKey.hideMenuBarTime)
    MenuBarTimeStyle.migrate(defaults)
    XCTAssertEqual(defaults.string(forKey: SettingsKey.menuBarTimeStyle), "iconOnly")
    XCTAssertEqual(MenuBarTimeStyle.current(defaults), .iconOnly)
    // The old key stays for Shortcuts and rollbacks.
    XCTAssertTrue(defaults.bool(forKey: SettingsKey.hideMenuBarTime))
  }

  func testNothingSetMeansMinutesAndSeconds() {
    MenuBarTimeStyle.migrate(defaults)
    XCTAssertEqual(MenuBarTimeStyle.current(defaults), .minutesSeconds)
    defaults.set(false, forKey: SettingsKey.hideMenuBarTime)
    defaults.removeObject(forKey: SettingsKey.menuBarTimeStyle)
    MenuBarTimeStyle.migrate(defaults)
    XCTAssertEqual(MenuBarTimeStyle.current(defaults), .minutesSeconds)
  }

  func testStoredStyleWinsOverTheOldSwitch() {
    defaults.set(true, forKey: SettingsKey.hideMenuBarTime)
    defaults.set("minutesOnly", forKey: SettingsKey.menuBarTimeStyle)
    MenuBarTimeStyle.migrate(defaults)
    XCTAssertEqual(MenuBarTimeStyle.current(defaults), .minutesOnly)
  }

  func testUnknownStoredValueFallsBack() {
    defaults.set("bogus", forKey: SettingsKey.menuBarTimeStyle)
    MenuBarTimeStyle.migrate(defaults)
    XCTAssertEqual(MenuBarTimeStyle.current(defaults), .minutesSeconds)
  }

  func testResetAllSettingsReturnsToMinutesAndSeconds() {
    defaults.set("iconOnly", forKey: SettingsKey.menuBarTimeStyle)
    defaults.set(true, forKey: SettingsKey.hideMenuBarTime)
    SettingsReset.perform(on: defaults, domain: suite)
    MenuBarTimeStyle.migrate(defaults)
    XCTAssertEqual(MenuBarTimeStyle.current(defaults), .minutesSeconds)
  }
}
