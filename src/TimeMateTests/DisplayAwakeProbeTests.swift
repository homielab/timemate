//  Created by homielab.com

import XCTest

@testable import TimeMate

final class DisplayAwakeProbeTests: XCTestCase {
  private func assertion(_ type: String, level: Int = 255) -> [String: Any] {
    ["AssertType": type, "AssertLevel": level]
  }

  func testAnotherAppKeepingTheDisplayOnCounts() {
    XCTAssertTrue(
      DisplayAwakeProbe.isKeptAwake(
        assertionsByPID: [42: [assertion("PreventUserIdleDisplaySleep")]], ownPID: 1))
    XCTAssertTrue(
      DisplayAwakeProbe.isKeptAwake(
        assertionsByPID: [42: [assertion("NoDisplaySleepAssertion")]], ownPID: 1))
  }

  func testOwnSystemSleepAndReleasedAssertionsDontCount() {
    XCTAssertFalse(
      DisplayAwakeProbe.isKeptAwake(
        assertionsByPID: [1: [assertion("PreventUserIdleDisplaySleep")]], ownPID: 1))
    XCTAssertFalse(
      DisplayAwakeProbe.isKeptAwake(
        assertionsByPID: [42: [assertion("PreventUserIdleSystemSleep")]], ownPID: 1))
    XCTAssertFalse(
      DisplayAwakeProbe.isKeptAwake(
        assertionsByPID: [42: [assertion("PreventUserIdleDisplaySleep", level: 0)]], ownPID: 1))
    XCTAssertFalse(DisplayAwakeProbe.isKeptAwake(assertionsByPID: [:], ownPID: 1))
  }

  private func named(_ process: String?, assertName: String? = nil) -> [String: Any] {
    var result = assertion("PreventUserIdleDisplaySleep")
    result["Process Name"] = process
    result["AssertName"] = assertName
    return result
  }

  func testKeepAwakeUtilitiesDontCount() {
    for name in ["caffeinate", "Amphetamine", "LUNGO", "KeepingYouAwake", "Caffeine", "theine"] {
      XCTAssertFalse(
        DisplayAwakeProbe.isKeptAwake(assertionsByPID: [42: [named(name)]], ownPID: 1), name)
      XCTAssertFalse(
        DisplayAwakeProbe.isKeptAwake(
          assertionsByPID: [42: [named(nil, assertName: name)]], ownPID: 1), name)
    }
  }

  func testCallNextToKeepAwakeUtilityCounts() {
    XCTAssertTrue(
      DisplayAwakeProbe.isKeptAwake(
        assertionsByPID: [42: [named("caffeinate")], 43: [named("zoom.us")]], ownPID: 1))
    XCTAssertTrue(
      DisplayAwakeProbe.isKeptAwake(
        assertionsByPID: [43: [named("Microsoft Teams", assertName: "Call in progress")]],
        ownPID: 1))
  }

  func testAssertionWithoutNameStillCounts() {
    XCTAssertTrue(
      DisplayAwakeProbe.isKeptAwake(assertionsByPID: [42: [named(nil)]], ownPID: 1))
  }

  /// The real query runs in the sandboxed test host without crashing.
  func testLiveQueryRunsInTheSandbox() {
    _ = DisplayAwakeProbe.isKeptAwakeByOtherApp()
  }
}
