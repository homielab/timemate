//  Created by homielab.com

import XCTest

@testable import TimeMate

final class TimerSnapshotTests: XCTestCase {
  private static let suiteName = "TimeMateTimerSnapshotTests"
  private var defaults: UserDefaults!
  private let end = Date(timeIntervalSince1970: 1_000_000)

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
  }

  override func tearDown() {
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = nil
    super.tearDown()
  }

  private func snapshot(
    state: PomodoroState = .active, endDate: Date?? = .none, remaining: Int = 5,
    totalDuration: Int = 10, focusSessionsCompleted: Int = 2
  ) -> TimerSnapshot {
    TimerSnapshot(
      state: state, sessionType: .focus,
      endDate: endDate ?? (state == .active ? end : nil), remaining: remaining,
      totalDuration: totalDuration, focusSessionsCompleted: focusSessionsCompleted,
      isBreakPostponed: false, isWaitingToContinue: false)
  }

  private var storedObject: Any? { defaults.object(forKey: SettingsKey.timerSnapshot) }

  // MARK: - isValid

  func testSensibleSnapshotOfEveryStateIsValid() {
    XCTAssertTrue(snapshot(state: .idle).isValid)
    XCTAssertTrue(snapshot(state: .active).isValid)
    XCTAssertTrue(snapshot(state: .paused).isValid)
    XCTAssertTrue(snapshot(state: .idle, remaining: 0, focusSessionsCompleted: 0).isValid)
    XCTAssertTrue(snapshot(state: .active, remaining: 0).isValid)
  }

  func testNonPositiveTotalDurationIsRejected() {
    for state in [PomodoroState.idle, .active, .paused] {
      XCTAssertFalse(snapshot(state: state, totalDuration: 0).isValid, "\(state)")
      XCTAssertFalse(snapshot(state: state, totalDuration: -10).isValid, "\(state)")
    }
  }

  func testNegativeRemainingIsRejected() {
    for state in [PomodoroState.idle, .active, .paused] {
      XCTAssertFalse(snapshot(state: state, remaining: -1).isValid, "\(state)")
    }
  }

  func testNegativeFocusSessionsCompletedIsRejected() {
    for state in [PomodoroState.idle, .active, .paused] {
      XCTAssertFalse(snapshot(state: state, focusSessionsCompleted: -1).isValid, "\(state)")
    }
  }

  func testIdleWithEndDateIsRejected() {
    XCTAssertFalse(snapshot(state: .idle, endDate: end).isValid)
  }

  func testActiveWithoutEndDateIsRejected() {
    XCTAssertFalse(snapshot(state: .active, endDate: .some(nil)).isValid)
  }

  func testPausedWithEndDateIsRejected() {
    XCTAssertFalse(snapshot(state: .paused, endDate: end).isValid)
  }

  func testPausedWithNothingLeftIsRejected() {
    XCTAssertFalse(snapshot(state: .paused, remaining: 0).isValid)
  }

  // MARK: - load

  func testLoadWithoutSavedSnapshotReturnsNil() {
    XCTAssertNil(TimerSnapshot.load(from: defaults))
    XCTAssertNil(storedObject)
  }

  func testLoadReturnsSavedSnapshotAndKeepsIt() {
    var saved = snapshot(state: .paused)
    saved.label = "Report"
    saved.lastActivity = end
    saved.save(to: defaults)

    XCTAssertEqual(TimerSnapshot.load(from: defaults), saved)
    XCTAssertNotNil(storedObject)
  }

  func testLoadRemovesDataThatDoesNotDecode() {
    for damaged: Any in [Data("not json".utf8), Data("{}".utf8), "text", 42] {
      defaults.set(damaged, forKey: SettingsKey.timerSnapshot)
      XCTAssertNil(TimerSnapshot.load(from: defaults), "\(damaged)")
      XCTAssertNil(storedObject, "\(damaged)")
    }
  }

  func testLoadRemovesInvalidSnapshot() {
    for invalid in [
      snapshot(totalDuration: 0), snapshot(remaining: -1), snapshot(focusSessionsCompleted: -1),
      snapshot(state: .idle, endDate: end), snapshot(state: .active, endDate: .some(nil)),
      snapshot(state: .paused, endDate: end), snapshot(state: .paused, remaining: 0),
    ] {
      invalid.save(to: defaults)
      XCTAssertNotNil(storedObject)
      XCTAssertNil(TimerSnapshot.load(from: defaults), "\(invalid)")
      XCTAssertNil(storedObject, "\(invalid)")
    }
  }

  // MARK: - Optional fields

  func testOptionalFieldsDefaultToNil() {
    let made = snapshot()
    XCTAssertNil(made.label)
    XCTAssertNil(made.lastActivity)
    XCTAssertNil(made.pausedAt)
  }

  func testSnapshotSavedBeforeOptionalFieldsExistedLoadsWithNil() throws {
    var full = snapshot(state: .paused)
    full.label = "Report"
    full.lastActivity = end
    full.pausedAt = end
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(full)) as? [String: Any])
    json["label"] = nil
    json["lastActivity"] = nil
    json["pausedAt"] = nil
    let old = try JSONSerialization.data(withJSONObject: json)
    defaults.set(old, forKey: SettingsKey.timerSnapshot)

    let loaded = try XCTUnwrap(TimerSnapshot.load(from: defaults))
    XCTAssertNil(loaded.label)
    XCTAssertNil(loaded.lastActivity)
    XCTAssertNil(loaded.pausedAt)
    XCTAssertEqual(loaded.state, .paused)
    XCTAssertEqual(loaded.remaining, 5)
  }
}
