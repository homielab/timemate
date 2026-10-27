//  Created by homielab.com

import XCTest

@testable import TimeMate

final class SessionSequenceTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_000_000)

  private typealias Position = SessionSequence.Position

  // MARK: - Next session

  func testCycleForEveryInterval() {
    for interval in 1...8 {
      var position = Position(sessionType: .focus, focusSessionsCompleted: 0)
      for round in 1...interval {
        position = SessionSequence.next(after: position, interval: interval)
        if round == interval {
          XCTAssertEqual(position, Position(sessionType: .longBreak, focusSessionsCompleted: 0))
        } else {
          XCTAssertEqual(
            position, Position(sessionType: .shortBreak, focusSessionsCompleted: round),
            "interval \(interval), round \(round)")
          position = SessionSequence.next(after: position, interval: interval)
          XCTAssertEqual(position, Position(sessionType: .focus, focusSessionsCompleted: round))
        }
      }
      position = SessionSequence.next(after: position, interval: interval)
      XCTAssertEqual(position, Position(sessionType: .focus, focusSessionsCompleted: 0))
    }
  }

  func testSkippingFocusCountsTowardsLongBreak() {
    let afterSkip = SessionSequence.next(
      after: Position(sessionType: .focus, focusSessionsCompleted: 3), interval: 4)
    XCTAssertEqual(afterSkip, Position(sessionType: .longBreak, focusSessionsCompleted: 0))
  }

  func testSkippingBreakKeepsCount() {
    for type in [SessionType.shortBreak, .longBreak] {
      let next = SessionSequence.next(
        after: Position(sessionType: type, focusSessionsCompleted: 2), interval: 4)
      XCTAssertEqual(next, Position(sessionType: .focus, focusSessionsCompleted: 2))
    }
  }

  // MARK: - Completion

  func testCompletionWaitsOnlyForBreaksWhenScreenStaysOpen() {
    XCTAssertEqual(
      SessionSequence.completion(of: .shortBreak, keepBreakScreenOpen: true), .waitOnBreakScreen)
    XCTAssertEqual(
      SessionSequence.completion(of: .longBreak, keepBreakScreenOpen: true), .waitOnBreakScreen)
    XCTAssertEqual(SessionSequence.completion(of: .focus, keepBreakScreenOpen: true), .advance)
    XCTAssertEqual(
      SessionSequence.completion(of: .shortBreak, keepBreakScreenOpen: false), .advance)
  }

  // MARK: - Extend and postpone

  private func countdown(
    type: SessionType = .shortBreak, state: PomodoroState = .active, total: Int = 300,
    remaining: Int = 100, end: Date? = nil, postponed: Bool = false, waiting: Bool = false
  ) -> SessionSequence.Countdown {
    SessionSequence.Countdown(
      sessionType: type, state: state, totalDuration: total, timeRemaining: remaining,
      endDate: state == .active ? (end ?? now.addingTimeInterval(100)) : nil,
      isBreakPostponed: postponed, isWaitingToContinue: waiting)
  }

  func testExtendRunningBreakPushesEndDate() throws {
    let result = try XCTUnwrap(SessionSequence.extend(countdown(), by: 60, now: now))
    XCTAssertEqual(result.state, .active)
    XCTAssertEqual(result.totalDuration, 360)
    XCTAssertEqual(result.timeRemaining, 160)
    XCTAssertEqual(result.endDate, now.addingTimeInterval(160))
    XCTAssertEqual(result.progress, 160.0 / 360.0, accuracy: 0.0001)
  }

  func testExtendPausedBreakAddsToRemaining() throws {
    let result = try XCTUnwrap(
      SessionSequence.extend(countdown(state: .paused), by: 60, now: now))
    XCTAssertEqual(result.state, .paused)
    XCTAssertEqual(result.timeRemaining, 160)
    XCTAssertEqual(result.totalDuration, 360)
    XCTAssertNil(result.endDate)
  }

  func testExtendWaitingBreakStartsAgainForExtra() throws {
    let result = try XCTUnwrap(
      SessionSequence.extend(countdown(state: .idle, waiting: true), by: 60, now: now))
    XCTAssertEqual(result.state, .active)
    XCTAssertEqual(result.totalDuration, 60)
    XCTAssertEqual(result.timeRemaining, 60)
    XCTAssertEqual(result.endDate, now.addingTimeInterval(60))
    XCTAssertEqual(result.progress, 1.0)
  }

  func testExtendRunningFocusPushesEndDate() throws {
    let result = try XCTUnwrap(
      SessionSequence.extend(
        countdown(type: .focus, total: 1500, remaining: 100), by: 300, now: now))
    XCTAssertEqual(result.state, .active)
    XCTAssertEqual(result.totalDuration, 1800)
    XCTAssertEqual(result.timeRemaining, 400)
    XCTAssertEqual(result.endDate, now.addingTimeInterval(400))
  }

  func testExtendPausedFocusAddsToRemaining() throws {
    let result = try XCTUnwrap(
      SessionSequence.extend(
        countdown(type: .focus, state: .paused, total: 1500, remaining: 100), by: 300, now: now))
    XCTAssertEqual(result.state, .paused)
    XCTAssertEqual(result.totalDuration, 1800)
    XCTAssertEqual(result.timeRemaining, 400)
    XCTAssertNil(result.endDate)
  }

  func testFocusExtendIsOfferedOnlyWhileRunningOrPaused() {
    XCTAssertTrue(SessionSequence.offersFocusExtend(sessionType: .focus, state: .active))
    XCTAssertTrue(SessionSequence.offersFocusExtend(sessionType: .focus, state: .paused))
    XCTAssertFalse(SessionSequence.offersFocusExtend(sessionType: .focus, state: .idle))
    XCTAssertFalse(SessionSequence.offersFocusExtend(sessionType: .shortBreak, state: .active))
  }

  func testExtendIgnoredWhenNotApplicable() {
    XCTAssertNil(SessionSequence.extend(countdown(type: .focus, state: .idle), by: 60, now: now))
    XCTAssertNil(SessionSequence.extend(countdown(postponed: true), by: 60, now: now))
    XCTAssertNil(SessionSequence.extend(countdown(state: .idle), by: 60, now: now))
    XCTAssertNil(SessionSequence.extend(countdown(), by: 0, now: now))
  }

  func testPostponeRestartsCountdownAtDelay() throws {
    let result = try XCTUnwrap(SessionSequence.postpone(countdown(), delay: 180, now: now))
    XCTAssertEqual(result.state, .active)
    XCTAssertEqual(result.totalDuration, 180)
    XCTAssertEqual(result.timeRemaining, 180)
    XCTAssertEqual(result.endDate, now.addingTimeInterval(180))
    XCTAssertEqual(result.progress, 1.0)
  }

  func testPostponeIgnoredWhenNotApplicable() {
    XCTAssertNil(SessionSequence.postpone(countdown(type: .focus), delay: 60, now: now))
    XCTAssertNil(SessionSequence.postpone(countdown(state: .paused), delay: 60, now: now))
    XCTAssertNil(SessionSequence.postpone(countdown(state: .idle), delay: 60, now: now))
    XCTAssertNil(SessionSequence.postpone(countdown(postponed: true), delay: 60, now: now))
    XCTAssertNil(SessionSequence.postpone(countdown(), delay: 0, now: now))
  }
}
