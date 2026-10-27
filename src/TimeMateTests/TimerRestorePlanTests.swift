//  Created by homielab.com

import XCTest

@testable import TimeMate

final class TimerRestorePlanTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_000_000)

  private func snapshot(
    state: PomodoroState, type: SessionType = .focus, end: Date? = nil, remaining: Int = 600,
    total: Int = 1500, postponed: Bool = false, waiting: Bool = false
  ) -> TimerSnapshot {
    TimerSnapshot(
      state: state, sessionType: type, endDate: end, remaining: remaining,
      totalDuration: total, focusSessionsCompleted: 1, isBreakPostponed: postponed,
      isWaitingToContinue: waiting)
  }

  private func plan(
    _ snapshot: TimerSnapshot, autoStart: Bool = true, keepBreakScreenOpen: Bool = false,
    autoStartPolicy: AutoStart? = nil
  ) -> TimerRestorePlan {
    TimerRestorePlan.make(
      from: snapshot, now: now,
      autoStart: autoStartPolicy ?? AutoStart(breaks: autoStart, focus: autoStart),
      keepBreakScreenOpen: keepBreakScreenOpen, overdueGracePeriod: 300)
  }

  func testIdleStaysIdle() {
    XCTAssertEqual(plan(snapshot(state: .idle)), .idle)
  }

  func testWaitingBreakScreenMovesOn() {
    XCTAssertEqual(
      plan(snapshot(state: .idle, type: .shortBreak, waiting: true)), .advanceFromWaitingBreak)
  }

  func testPausedKeepsRemainingCappedAtTotal() {
    XCTAssertEqual(
      plan(snapshot(state: .paused, remaining: 600)),
      .paused(remaining: 600, totalDuration: 1500, isBreakPostponed: false))
    XCTAssertEqual(
      plan(snapshot(state: .paused, remaining: 9000, postponed: true)),
      .paused(remaining: 1500, totalDuration: 1500, isBreakPostponed: true))
  }

  func testActiveWithTimeLeftResumes() {
    let end = now.addingTimeInterval(600)
    XCTAssertEqual(
      plan(snapshot(state: .active, end: end)),
      .resume(endDate: end, remaining: 600, totalDuration: 1500, isBreakPostponed: false))
  }

  func testClockSetBackCannotStretchSession() {
    let end = now.addingTimeInterval(100_000)
    XCTAssertEqual(
      plan(snapshot(state: .active, end: end)),
      .resume(
        endDate: now.addingTimeInterval(1500), remaining: 1500, totalDuration: 1500,
        isBreakPostponed: false))
  }

  func testPostponedBreakResumesWhileDue() {
    let end = now.addingTimeInterval(60)
    XCTAssertEqual(
      plan(snapshot(state: .active, type: .shortBreak, end: end, total: 180, postponed: true)),
      .resume(endDate: end, remaining: 60, totalDuration: 180, isBreakPostponed: true))
  }

  func testPostponedBreakThatCameDueWaits() {
    let end = now.addingTimeInterval(-5)
    XCTAssertEqual(
      plan(snapshot(state: .active, type: .shortBreak, end: end, total: 180, postponed: true)),
      .postponedBreakDue)
  }

  func testExpiredSessionIsRecordedAndNextStarts() {
    let end = now.addingTimeInterval(-30)
    XCTAssertEqual(
      plan(snapshot(state: .active, end: end)),
      .expired(endDate: end, duration: 1500, startNext: true))
    XCTAssertEqual(
      plan(snapshot(state: .active, end: now), autoStart: true),
      .expired(endDate: now, duration: 1500, startNext: true))
  }

  func testExpiredSessionDoesNotStartWithoutAutoStart() {
    let end = now.addingTimeInterval(-30)
    XCTAssertEqual(
      plan(snapshot(state: .active, end: end), autoStart: false),
      .expired(endDate: end, duration: 1500, startNext: false))
  }

  func testExpiredBreakWaitsOnScreenWhenKeptOpen() {
    let end = now.addingTimeInterval(-30)
    XCTAssertEqual(
      plan(snapshot(state: .active, type: .longBreak, end: end), keepBreakScreenOpen: true),
      .expired(endDate: end, duration: 1500, startNext: false))
    // A focus session is not held back by the break-screen setting.
    XCTAssertEqual(
      plan(snapshot(state: .active, type: .focus, end: end), keepBreakScreenOpen: true),
      .expired(endDate: end, duration: 1500, startNext: true))
  }

  func testExpiredLongerThanGracePeriodDoesNotStartNext() {
    let atLimit = now.addingTimeInterval(-300)
    XCTAssertEqual(
      plan(snapshot(state: .active, end: atLimit)),
      .expired(endDate: atLimit, duration: 1500, startNext: true))
    let pastLimit = now.addingTimeInterval(-301)
    XCTAssertEqual(
      plan(snapshot(state: .active, end: pastLimit)),
      .expired(endDate: pastLimit, duration: 1500, startNext: false))
  }

  func testActiveWithoutEndDateStaysIdle() {
    XCTAssertEqual(plan(snapshot(state: .active, end: nil)), .idle)
  }

  func testExpiredSessionStartsNextOnlyWhenItsKindIsOn() {
    let focusEnded = snapshot(state: .active, type: .focus, end: now.addingTimeInterval(-60))
    let breakEnded = snapshot(state: .active, type: .shortBreak, end: now.addingTimeInterval(-60))
    let breaksOnly = AutoStart(breaks: true, focus: false)
    XCTAssertEqual(
      plan(focusEnded, autoStartPolicy: breaksOnly),
      .expired(endDate: now.addingTimeInterval(-60), duration: 1500, startNext: true))
    XCTAssertEqual(
      plan(breakEnded, autoStartPolicy: breaksOnly),
      .expired(endDate: now.addingTimeInterval(-60), duration: 1500, startNext: false))
  }
}
