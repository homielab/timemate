//  Created by homielab.com

import AppKit
import XCTest

@testable import TimeMate

/// Settings resets, custom durations and the session history.
final class PomodoroTimerSettingsTests: TimerTestCase {
  // MARK: - Reset All Settings

  func testResetKeepsTimerSnapshotAndGoalNotificationDate() {
    timer = makeTimer(focus: 120)
    timer.startTimer()
    runTicks(timer, 20)
    let notified = Date(timeIntervalSince1970: 123)
    defaults.set(notified, forKey: SettingsKey.dailyGoalNotifiedAt)
    defaults.set(true, forKey: SettingsKey.hasLaunchedBefore)
    defaults.set(true, forKey: SettingsKey.pauseOnSleep)
    defaults.set(40, forKey: SettingsKey.overlaySkipDelay)

    SettingsReset.perform(on: defaults, domain: Self.suiteName)

    XCTAssertNil(defaults.object(forKey: SettingsKey.pauseOnSleep))
    XCTAssertNil(defaults.object(forKey: SettingsKey.overlaySkipDelay))
    XCTAssertEqual(defaults.object(forKey: SettingsKey.dailyGoalNotifiedAt) as? Date, notified)
    XCTAssertTrue(defaults.bool(forKey: SettingsKey.hasLaunchedBefore))
    let relaunched = makeTimer(focus: 120)
    XCTAssertEqual(relaunched.state, .active)
    XCTAssertEqual(relaunched.timeRemaining, 100)
  }

  func testResetWithoutStateKeysDoesNotCreateThem() {
    defaults.removeObject(forKey: SettingsKey.timerSnapshot)
    defaults.set(5, forKey: SettingsKey.focusDuration)
    SettingsReset.perform(on: defaults, domain: Self.suiteName)
    XCTAssertNil(defaults.object(forKey: SettingsKey.timerSnapshot))
    XCTAssertNil(defaults.object(forKey: SettingsKey.focusDuration))
  }

  func testTimerReadsLiveFromInjectedDefaults() {
    timer.startTimer()
    defaults.set(6, forKey: SettingsKey.focusDuration)
    timer.stopTimer()  // resets with the new duration
    XCTAssertEqual(timer.timeRemaining, 6)
  }

  // MARK: - Custom durations

  func testNinetyMinuteFocusThenTenMinuteBreak() {
    timer = makeTimer(focus: 90, short: 10)
    XCTAssertEqual(timer.timeRemaining, 90)
    timer.startTimer()
    runTicks(timer, 89)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.timeRemaining, 1)
    runTicks(timer, 1)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.timeRemaining, 10)
    XCTAssertEqual(timer.state, .active)
  }

  func testFiftyMinuteFocusUsesTheExactLength() {
    timer = makeTimer(focus: 50, short: 10)
    XCTAssertEqual(timer.timeRemaining, 50)
  }

  func testZeroStoredDurationRunsForOneMinute() {
    timer = makeTimer(focus: 3, short: 0)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.timeRemaining, 1)
  }

  func testHugeStoredDurationRunsForADay() {
    timer = makeTimer(focus: Int.max / 30, short: 600)
    XCTAssertEqual(timer.timeRemaining, 1440)
    XCTAssertEqual(timer.durationFor(session: .focus), PomodoroTimer.seconds(forMinutes: 1440))
    XCTAssertEqual(timer.durationFor(session: .shortBreak), PomodoroTimer.seconds(forMinutes: 600))
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

  func testSessionsSkippedBeforeHalfAreNotRecorded() {
    timer.startTimer()
    runTicks(timer, 1)
    timer.skipSession()  // focus skipped before half
    timer.skipSession()  // short break skipped

    XCTAssertEqual(history.records, [])
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
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
