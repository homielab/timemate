//  Created by homielab.com

import XCTest

@testable import TimeMate

/// "Undo Last Session" takes the session off the current cycle too.
final class PomodoroTimerUndoTests: TimerTestCase {
  private func runFocusAndBreak() {
    timer.startTimer()
    finishSession(timer)
    timer.startTimer()
    finishSession(timer)
  }

  private func undoLast() -> SessionHistory.Record? {
    guard let last = history.lastFocusRecord else { return nil }
    return timer.undoLastFocusSession(matching: last)
  }

  func testUndoAfterThreeSessionsLeavesTwoAndLongBreakAfterTheRealFourth() {
    timer = makeTimer(autoStart: false)
    for _ in 0..<3 { runFocusAndBreak() }
    XCTAssertEqual(timer.focusSessionsCompleted, 3)
    XCTAssertNotNil(undoLast())
    XCTAssertEqual(timer.focusSessionsCompleted, 2)
    XCTAssertEqual(TimerSnapshot.load(from: defaults)?.focusSessionsCompleted, 2)
    runFocusAndBreak()
    XCTAssertEqual(timer.focusSessionsCompleted, 3)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .longBreak)
  }

  func testUndoSessionBeforeLongBreakKeepsCurrentCycle() {
    timer = makeTimer(autoStart: false)
    for _ in 0..<4 { runFocusAndBreak() }
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
    advanceClock(by: 60)
    XCTAssertNotNil(undoLast())
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
    runFocusAndBreak()
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertNotNil(undoLast())
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
  }

  func testUndoSessionBeforeRestartKeepsCurrentCycle() {
    timer = makeTimer(autoStart: false)
    for _ in 0..<2 { runFocusAndBreak() }
    advanceClock(by: 60)
    timer.restartCycle()
    advanceClock(by: 60)
    runFocusAndBreak()
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertNotNil(undoLast())
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
    XCTAssertNotNil(undoLast())
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
  }
}
