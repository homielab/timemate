//  Created by homielab.com

import XCTest

@testable import TimeMate

final class PomodoroTimerTests: XCTestCase {
  private static let suiteName = "TimeMateTests"

  private var defaults: UserDefaults!
  private var currentTime: Date!
  private var timer: PomodoroTimer!

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
    currentTime = Date(timeIntervalSince1970: 1_000_000)
    timer = makeTimer()
  }

  override func tearDown() {
    timer = nil
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  // MARK: - Helpers

  /// Debug builds count one tick per minute value (`durationFor` uses minutes as
  /// seconds under DEBUG), so focus 3 finishes after 3 countdown ticks plus one
  /// firing tick.
  private func makeTimer(
    focus: Int = 3, short: Int = 2, long: Int = 4, interval: Int = 4,
    autoStart: Bool = true, keepBreakOpen: Bool = false
  ) -> PomodoroTimer {
    defaults.set(focus, forKey: SettingsKey.focusDuration)
    defaults.set(short, forKey: SettingsKey.shortBreakDuration)
    defaults.set(long, forKey: SettingsKey.longBreakDuration)
    defaults.set(interval, forKey: SettingsKey.longBreakInterval)
    defaults.set(autoStart, forKey: SettingsKey.autoStartNextSession)
    defaults.set(keepBreakOpen, forKey: SettingsKey.keepBreakScreenOpen)
    defaults.set(false, forKey: SettingsKey.notificationsEnabled)
    defaults.set("Glass", forKey: SettingsKey.alarmSound)
    defaults.set(0.0, forKey: SettingsKey.alarmVolume)
    return PomodoroTimer(
      defaults: defaults,
      now: { [weak self] in
        self?.currentTime ?? Date(timeIntervalSince1970: 0)
      })
  }

  private func runTicks(_ timer: PomodoroTimer, _ count: Int) {
    for _ in 0..<count {
      timer.handleTick()
    }
  }

  private func finishSession(_ timer: PomodoroTimer) {
    runTicks(timer, timer.timeRemaining + 1)
  }

  // MARK: - Initial state

  func testInitialStateIsIdleFocusAtFullDuration() {
    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.timeRemaining, 3)
    XCTAssertEqual(timer.progress, 1.0)
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
    XCTAssertFalse(timer.isWaitingToContinue)
  }

  // MARK: - Ticking and session progression

  func testTicksCountDownAndUpdateProgress() {
    timer.startTimer()
    runTicks(timer, 2)
    XCTAssertEqual(timer.timeRemaining, 1)
    XCTAssertEqual(timer.progress, 1.0 / 3.0, accuracy: 0.0001)
  }

  func testCompletedFocusMovesToShortBreakAndAutoStarts() {
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 2)
  }

  func testCompletedShortBreakMovesBackToFocus() {
    timer.startTimer()
    finishSession(timer)
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 3)
  }

  func testLongBreakAfterReachingInterval() {
    timer = makeTimer(focus: 2, short: 1, interval: 2)
    timer.startTimer()
    finishSession(timer)  // focus 1 -> short break
    finishSession(timer)  // short break -> focus 2
    finishSession(timer)  // focus 2 -> long break (interval reached)
    XCTAssertEqual(timer.currentSessionType, .longBreak)
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 4)
  }

  func testLongBreakOnlyAfterFullIntervalOfEight() {
    timer = makeTimer(focus: 2, short: 1, interval: 8)
    timer.startTimer()
    for cycle in 1...8 {
      finishSession(timer)  // finish the focus session
      if cycle < 8 {
        XCTAssertEqual(timer.currentSessionType, .shortBreak)
        finishSession(timer)  // finish the short break
        XCTAssertEqual(timer.currentSessionType, .focus)
      }
    }
    XCTAssertEqual(timer.currentSessionType, .longBreak)
  }

  func testLongBreakMovesBackToFocusAfterwards() {
    timer = makeTimer(focus: 2, short: 1, interval: 1)
    timer.startTimer()
    finishSession(timer)  // focus -> long break
    XCTAssertEqual(timer.currentSessionType, .longBreak)
    finishSession(timer)  // long break -> focus
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
  }

  // MARK: - Auto-start

  func testAutoStartOffLeavesNextSessionIdle() {
    timer = makeTimer(autoStart: false)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(timer.timeRemaining, 2)
  }

  func testKeepBreakScreenOpenHoldsBreakAtIdle() {
    timer = makeTimer(keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)  // focus -> short break, auto-started
    finishSession(timer)  // short break hits zero -> keep-open branch
    XCTAssertTrue(timer.isWaitingToContinue)
    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    timer.continueWork()
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
  }

  func testKeepBreakScreenOpenOffAdvancesImmediately() {
    timer = makeTimer(keepBreakOpen: false)
    timer.startTimer()
    finishSession(timer)
    finishSession(timer)
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
  }

  // MARK: - Continue work

  func testContinueWorkStartsTimerOnceWhenAutoStartOff() {
    timer = makeTimer(autoStart: false, keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    finishSession(timer)  // the held short break sets the waiting flag
    XCTAssertTrue(timer.isWaitingToContinue)
    timer.continueWork()
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.timeRemaining, 3)
    // Exactly one ticking loop: one manual tick decrements by one, not by two.
    timer.handleTick()
    XCTAssertEqual(timer.timeRemaining, 2)
  }

  func testContinueWorkAfterWaitingBreakAdvancesOnce() {
    timer = makeTimer(keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    finishSession(timer)
    XCTAssertTrue(timer.isWaitingToContinue)
    timer.continueWork()
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 3)
    timer.handleTick()
    XCTAssertEqual(timer.timeRemaining, 2)
  }

  // MARK: - Pause / resume

  func testPauseKeepsRemainingTime() {
    timer.startTimer()
    runTicks(timer, 2)
    timer.pauseTimer()
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 1)
  }

  func testResumeContinuesFromRemainingTime() {
    timer.startTimer()
    runTicks(timer, 2)
    timer.pauseTimer()
    timer.startTimer()  // state == .paused -> no reset
    XCTAssertEqual(timer.timeRemaining, 1)
    timer.handleTick()
    XCTAssertEqual(timer.timeRemaining, 0)
    timer.handleTick()  // session fires
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
  }

  // MARK: - Restart / skip / stop

  func testRestartCycleResetsEverything() {
    timer.startTimer()
    finishSession(timer)  // focus -> short break, completed 1
    timer.restartCycle()
    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
    XCTAssertEqual(timer.timeRemaining, 3)
    XCTAssertEqual(timer.progress, 1.0)
    XCTAssertFalse(timer.isWaitingToContinue)
  }

  func testSkipSessionCountsFocusAndAdvances() {
    timer.startTimer()
    timer.skipSession()
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
  }

  func testStopTimerResetsSession() {
    timer.startTimer()
    runTicks(timer, 1)
    timer.stopTimer()
    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(timer.timeRemaining, 3)
    XCTAssertEqual(timer.progress, 1.0)
    XCTAssertFalse(timer.isWaitingToContinue)
  }

  // MARK: - Injected clock

  func testInjectedClockStampsEachTick() {
    let first = Date(timeIntervalSince1970: 5_000)
    let second = first.addingTimeInterval(7)
    currentTime = first
    timer.startTimer()
    timer.handleTick()
    XCTAssertEqual(timer.lastTickAt, first)
    currentTime = second
    timer.handleTick()
    XCTAssertEqual(timer.lastTickAt, second)
  }

  func testTimerReadsLiveFromInjectedDefaults() {
    timer.startTimer()
    defaults.set(6, forKey: SettingsKey.focusDuration)
    timer.stopTimer()  // resets with the new duration
    XCTAssertEqual(timer.timeRemaining, 6)
  }
}
