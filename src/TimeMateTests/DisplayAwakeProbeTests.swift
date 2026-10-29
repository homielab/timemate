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

  /// The real query runs in the sandboxed test host without crashing.
  func testLiveQueryRunsInTheSandbox() {
    _ = DisplayAwakeProbe.isKeptAwakeByOtherApp()
  }
}
