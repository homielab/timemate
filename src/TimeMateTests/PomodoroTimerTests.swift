//  Created by homielab.com

import AppKit
import XCTest

@testable import TimeMate

final class PomodoroTimerTests: XCTestCase {
  private static let suiteName = "TimeMateTests"

  private var defaults: UserDefaults!
  private var currentTime: Date!
  private var workspaceCenter: NotificationCenter!
  private var history: SessionHistory!
  private var timer: PomodoroTimer!

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
    currentTime = Date(timeIntervalSince1970: 1_000_000)
    workspaceCenter = NotificationCenter()
    history = SessionHistory(
      fileURL: nil,
      now: { [weak self] in self?.currentTime ?? Date(timeIntervalSince1970: 0) })
    timer = makeTimer()
  }

  override func tearDown() {
    timer = nil
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  // MARK: - Helpers

  /// Debug builds use minute values as seconds (`durationFor` under DEBUG), so
  /// focus 3 lasts 3 seconds of the fake clock: it finishes on the third tick.
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
      },
      workspaceNotificationCenter: workspaceCenter,
      history: history)
  }

  /// Advances the fake clock one second per tick, like the real 1 s timer.
  private func runTicks(_ timer: PomodoroTimer, _ count: Int) {
    for _ in 0..<count {
      advanceClock(by: 1)
      timer.handleTick()
    }
  }

  private func advanceClock(by seconds: TimeInterval) {
    currentTime = currentTime.addingTimeInterval(seconds)
  }

  private func finishSession(_ timer: PomodoroTimer) {
    runTicks(timer, timer.timeRemaining)
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
    timer.startTimer()  // auto-start is off: the user starts the break
    finishSession(timer)  // the held short break sets the waiting flag
    XCTAssertTrue(timer.isWaitingToContinue)
    timer.continueWork()
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.timeRemaining, 3)
    // Exactly one ticking loop: one second decrements by one, not by two.
    runTicks(timer, 1)
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
    runTicks(timer, 1)
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
    runTicks(timer, 1)  // remaining reaches zero -> session fires
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
  }

  func testTimeSpentPausedDoesNotCount() {
    timer = makeTimer(focus: 1500)
    timer.startTimer()
    runTicks(timer, 100)
    timer.pauseTimer()
    advanceClock(by: 3600)
    timer.handleTick()  // a stray tick while paused changes nothing
    XCTAssertEqual(timer.timeRemaining, 1400)
    timer.startTimer()
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(1400))
    runTicks(timer, 10)
    XCTAssertEqual(timer.timeRemaining, 1390)
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

  // MARK: - Wall-clock end date (sleep / App Nap)

  func testClockJumpOfTenMinutesDropsRemainingByTenMinutes() {
    timer = makeTimer(focus: 1500)
    timer.startTimer()
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(1500))
    advanceClock(by: 600)
    timer.handleTick()
    XCTAssertEqual(timer.timeRemaining, 900)
    XCTAssertEqual(timer.progress, 0.6, accuracy: 0.0001)
    XCTAssertEqual(timer.state, .active)
  }

  func testDelayedTicksDoNotStretchTheSession() {
    timer = makeTimer(focus: 10)
    timer.startTimer()
    // App Nap: only two ticks get through over the whole session length.
    advanceClock(by: 4)
    timer.handleTick()
    XCTAssertEqual(timer.timeRemaining, 6)
    advanceClock(by: 6)
    timer.handleTick()
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
  }

  func testJumpPastEndDateFinishesSessionExactlyOnce() {
    timer = makeTimer(autoStart: false)
    var sessionChanges = 0
    let cancellable = timer.$currentSessionType.dropFirst().sink { _ in sessionChanges += 1 }
    timer.startTimer()
    advanceClock(by: 3600)
    timer.handleTick()
    timer.handleTick()
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(sessionChanges, 1)
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(timer.timeRemaining, 2)
    cancellable.cancel()
  }

  func testWakeAfterEndDateFinishesSessionOnceWithoutATick() {
    timer.startTimer()
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    advanceClock(by: 3600)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 2)
    // A second wake (or the timer's late fire) must not finish the next session.
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    timer.handleTick()
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.timeRemaining, 2)
  }

  func testWakeBeforeEndDateShowsRealRemainingTime() {
    timer = makeTimer(focus: 120)
    timer.startTimer()
    runTicks(timer, 5)
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    advanceClock(by: 60)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(timer.timeRemaining, 55)
    XCTAssertEqual(timer.state, .active)
  }

  func testWakeWhilePausedKeepsRemainingTime() {
    timer = makeTimer(focus: 120)
    timer.startTimer()
    runTicks(timer, 20)
    timer.pauseTimer()
    advanceClock(by: 600)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 100)
  }

  func testTimerReadsLiveFromInjectedDefaults() {
    timer.startTimer()
    defaults.set(6, forKey: SettingsKey.focusDuration)
    timer.stopTimer()  // resets with the new duration
    XCTAssertEqual(timer.timeRemaining, 6)
  }

  // MARK: - Session history

  func testCompletedSessionsAreRecordedWithTheirKind() {
    timer.startTimer()
    let focusEnd = currentTime.addingTimeInterval(3)
    finishSession(timer)  // focus 3 s
    finishSession(timer)  // short break 2 s

    XCTAssertEqual(history.records.map(\.kind), [.focus, .short])
    XCTAssertEqual(history.records.first?.end, focusEnd)
    XCTAssertEqual(history.records.first?.duration, 3)
    XCTAssertEqual(history.todayTotals().pomodoros, 1)
    XCTAssertEqual(history.todayTotals().focusSeconds, 3)
  }

  func testSkippedSessionsAreNotRecorded() {
    timer.startTimer()
    runTicks(timer, 1)
    timer.skipSession()  // focus skipped
    timer.skipSession()  // short break skipped

    XCTAssertEqual(history.records, [])
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
  }

  func testPausedTimeIsNotCountedAsFocus() {
    timer.startTimer()
    runTicks(timer, 1)
    timer.pauseTimer()
    advanceClock(by: 600)
    timer.startTimer()
    finishSession(timer)

    XCTAssertEqual(history.records.count, 1)
    XCTAssertEqual(history.records.first?.duration, 3)
    XCTAssertEqual(history.records.first?.end, currentTime)
  }

  func testBreakHeldOnBreakScreenIsRecordedOnce() {
    timer = makeTimer(keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    finishSession(timer)  // short break ends, waits on the break screen
    XCTAssertTrue(timer.isWaitingToContinue)
    timer.continueWork()

    XCTAssertEqual(history.records.map(\.kind), [.focus, .short])
  }

  func testSessionEndingDuringSleepIsRecordedAtItsEnd() {
    timer.startTimer()
    let focusEnd = currentTime.addingTimeInterval(3)
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    advanceClock(by: 3600)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

    XCTAssertEqual(history.records.count, 1)
    XCTAssertEqual(history.records.first?.end, focusEnd)
  }
}
