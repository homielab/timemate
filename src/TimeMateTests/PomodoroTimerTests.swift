//  Created by homielab.com

import AppKit
import XCTest

@testable import TimeMate

/// Core timer behavior: ticking, session progression, controls and labels.
final class PomodoroTimerTests: TimerTestCase {
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

  func testStopTimerOnAWaitingBreakReturnsToFocus() {
    timer = makeTimer(keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    finishSession(timer)
    XCTAssertTrue(timer.isWaitingToContinue)
    timer.stopTimer()
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .idle)
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.timeRemaining, 3)
  }

  func testKeepBreakScreenOpenWithOverlayOffStartsFocusAutomatically() {
    defaults.set(false, forKey: SettingsKey.overlayEnabled)
    timer = makeTimer(keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)  // focus -> short break
    finishSession(timer)  // break ends: nothing to wait on
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
  }

  func testBreakScreenCannotShowWhileAFullScreenAppHoldsItBack() {
    defaults.set(true, forKey: SettingsKey.overlaySkipFullscreen)
    timer = makeTimer(keepBreakOpen: true)
    XCTAssertTrue(timer.breakScreenCanShow)
    let fullscreen = PomodoroTimer(
      defaults: defaults, now: { Date(timeIntervalSince1970: 0) },
      workspaceNotificationCenter: NotificationCenter(), playSound: { _, _ in },
      isFullscreenProbe: { true })
    XCTAssertFalse(fullscreen.breakScreenCanShow)
    defaults.set(false, forKey: SettingsKey.overlaySkipFullscreen)
    XCTAssertTrue(fullscreen.breakScreenCanShow)
  }

  func testBreakScreenCannotShowDuringACallWithWaitDuringCalls() {
    defaults.set(false, forKey: SettingsKey.overlaySkipFullscreen)
    displayKeptAwake = true
    timer = makeTimer(keepBreakOpen: true)
    XCTAssertTrue(timer.breakScreenCanShow, "Off by default")
    defaults.set(true, forKey: SettingsKey.overlayWaitDuringCalls)
    XCTAssertFalse(timer.breakScreenCanShow)
    displayKeptAwake = false
    XCTAssertTrue(timer.breakScreenCanShow)
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

  // MARK: - Popover main button

  func testPopoverMainButtonContinuesWorkAfterAWaitingBreak() {
    timer = makeTimer(keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    finishSession(timer)
    XCTAssertTrue(timer.isWaitingToContinue)
    let model = PopoverTimerModel(timer: timer)
    XCTAssertEqual(model.mainAction, .continueWork)
    model.performMainAction()
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 3)
    XCTAssertEqual(model.mainAction, .pause)
  }

  func testPopoverMainButtonStartsPausesAndResumes() {
    let model = PopoverTimerModel(timer: timer)
    XCTAssertEqual(model.mainAction, .start)
    model.performMainAction()
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(model.mainAction, .pause)
    model.performMainAction()
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(model.mainAction, .resume)
    model.performMainAction()
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.currentSessionType, .focus)
  }

  // MARK: - Durations changed in Settings

  func testIdleTimerShowsANewDurationRightAway() {
    XCTAssertEqual(timer.secondsRemaining, 3)
    defaults.set(50, forKey: SettingsKey.focusDuration)
    XCTAssertEqual(timer.secondsRemaining, 50)
    XCTAssertEqual(timer.progress, 1.0)
    XCTAssertTrue(history.records.isEmpty)
    timer.startTimer()
    XCTAssertEqual(timer.secondsRemaining, 50)
  }

  func testOtherSessionDurationsDoNotTouchTheIdleTimer() {
    defaults.set(9, forKey: SettingsKey.shortBreakDuration)
    XCTAssertEqual(timer.secondsRemaining, 3)
  }

  func testRunningAndPausedSessionsKeepTheirLength() {
    timer.startTimer()
    defaults.set(50, forKey: SettingsKey.focusDuration)
    XCTAssertEqual(timer.secondsRemaining, 3)
    runTicks(timer, 1)
    timer.pauseTimer()
    defaults.set(60, forKey: SettingsKey.focusDuration)
    XCTAssertEqual(timer.secondsRemaining, 2)
  }

  func testWaitingBreakScreenKeepsItsStateWhenDurationsChange() {
    timer = makeTimer(keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    finishSession(timer)
    XCTAssertTrue(timer.isWaitingToContinue)
    defaults.set(7, forKey: SettingsKey.shortBreakDuration)
    XCTAssertEqual(timer.timeRemaining, 0)
    XCTAssertTrue(timer.isWaitingToContinue)
  }

  func testWaitingBreakScreenStaysWhenFocusOrLongBreakDurationChanges() {
    timer = makeTimer(keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    finishSession(timer)
    defaults.set(40, forKey: SettingsKey.focusDuration)
    defaults.set(20, forKey: SettingsKey.longBreakDuration)
    XCTAssertTrue(timer.isWaitingToContinue)
    XCTAssertEqual(timer.timeRemaining, 0)
    timer.continueWork()
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

  // MARK: - Start or continue

  func testStartOrContinueStartsAnIdleTimer() {
    timer.startOrContinue()
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.timeRemaining, 3)
  }

  func testStartOrContinueMovesPastAWaitingBreak() {
    timer = makeTimer(keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    finishSession(timer)
    XCTAssertTrue(timer.isWaitingToContinue)
    timer.startOrContinue()
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 3)
  }

  func testStartOrContinueNeverPausesARunningTimer() {
    timer.startTimer()
    runTicks(timer, 1)
    timer.startOrContinue()
    XCTAssertEqual(timer.state, .active)
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
    timer = makeTimer(focus: 1200)
    timer.startTimer()
    runTicks(timer, 100)
    timer.pauseTimer()
    advanceClock(by: 3600)
    timer.handleTick()  // a stray tick while paused changes nothing
    XCTAssertEqual(timer.timeRemaining, 1100)
    timer.startTimer()
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(1100))
    runTicks(timer, 10)
    XCTAssertEqual(timer.timeRemaining, 1090)
  }

  func testPausedSessionRecordsItsRealStart() {
    timer = makeTimer(focus: 1200)
    let began = currentTime!
    timer.startTimer()
    runTicks(timer, 600)
    timer.pauseTimer()
    advanceClock(by: 1800)
    timer.startTimer()
    finishSession(timer)
    let record = history.records.last
    XCTAssertEqual(record?.start, began)
    XCTAssertEqual(record?.end, began.addingTimeInterval(1200 + 1800))
    XCTAssertEqual(record?.duration, 1200)
  }

  func testUnpausedSessionStartsAtEndMinusLength() {
    timer = makeTimer(focus: 1200)
    let began = currentTime!
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(history.records.last?.start, began)
    XCTAssertEqual(history.records.last?.duration, 1200)
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
    runTicks(timer, 2)
    timer.skipSession()
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
  }

  func testSkipIdleFocusDoesNotCountIt() {
    timer.skipSession()
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
  }

  func testSkipPausedFocusPastHalfCountsIt() {
    timer.startTimer()
    runTicks(timer, 2)
    timer.pauseTimer()
    timer.skipSession()
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
  }

  func testSkipNextDayRecordsPausedFocusAtItsPause() {
    timer.startTimer()
    runTicks(timer, 2)
    timer.pauseTimer()
    let pausedAt = currentTime!
    advanceClock(by: 16 * 3600)  // paused in the afternoon, skipped next morning
    timer.skipSession()
    XCTAssertEqual(history.records.count, 1)
    XCTAssertEqual(history.records.first?.end, pausedAt)
    XCTAssertEqual(history.todayTotals().pomodoros, 0)
  }

  func testRecordAndResetNextDayRecordsPausedFocusAtItsPause() {
    timer.startTimer()
    runTicks(timer, 2)
    timer.pauseTimer()
    let pausedAt = currentTime!
    advanceClock(by: 16 * 3600)
    timer.stopTimer(recording: true)
    XCTAssertEqual(history.records.first?.end, pausedAt)
    XCTAssertEqual(history.todayTotals().pomodoros, 0)
  }

  func testSkipFocusPastHalfRecordsTheTimeItRan() {
    defaults.set("Write report", forKey: SettingsKey.sessionLabel)
    timer.startTimer()
    runTicks(timer, 2)
    timer.skipSession()
    XCTAssertEqual(history.records.count, 1)
    XCTAssertEqual(history.records.first?.seconds, 2)
    XCTAssertEqual(history.records.first?.end, currentTime)
    XCTAssertEqual(history.records.first?.label, "Write report")
    XCTAssertEqual(history.todayTotals().pomodoros, 1)
  }

  func testResetFocusPastHalfAsksAndRecordingAddsOneRecord() {
    defaults.set("Write report", forKey: SettingsKey.sessionLabel)
    timer.startTimer()
    runTicks(timer, 2)
    XCTAssertTrue(timer.resetNeedsConfirmation)
    timer.stopTimer(recording: true)
    XCTAssertEqual(history.records.count, 1)
    XCTAssertEqual(history.records.first?.seconds, 2)
    XCTAssertEqual(history.records.first?.label, "Write report")
    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertFalse(timer.resetNeedsConfirmation)
  }

  func testResetFocusPastHalfWithoutRecordingRecordsNothing() {
    timer.startTimer()
    runTicks(timer, 2)
    timer.stopTimer()
    XCTAssertTrue(history.records.isEmpty)
  }

  func testResetFocusBeforeHalfDoesNotAskOrRecord() {
    timer.startTimer()
    runTicks(timer, 1)
    XCTAssertFalse(timer.resetNeedsConfirmation)
    timer.stopTimer(recording: true)
    XCTAssertTrue(history.records.isEmpty)
  }

  func testResetBreakNeverAsks() {
    timer.startTimer()
    finishSession(timer)
    timer.startTimer()
    runTicks(timer, 1)
    XCTAssertFalse(timer.resetNeedsConfirmation)
  }

  func testHotKeyResetRecordsFocusPastHalf() {
    timer.startTimer()
    runTicks(timer, 2)
    _ = timer.perform(.reset)
    XCTAssertEqual(history.records.count, 1)
  }

  func testSkipFocusBeforeHalfRecordsNothing() {
    timer.startTimer()
    runTicks(timer, 1)
    timer.skipSession()
    XCTAssertTrue(history.records.isEmpty)
    XCTAssertEqual(history.todayTotals().pomodoros, 0)
  }

  func testSkipBreakRecordsNothing() {
    timer.startTimer()
    finishSession(timer)
    timer.startTimer()
    runTicks(timer, 1)
    timer.skipSession()
    XCTAssertEqual(history.records.count, 1)
  }

  func testSkipPausedFocusBeforeHalfDoesNotCountIt() {
    timer.startTimer()
    runTicks(timer, 1)
    timer.pauseTimer()
    timer.skipSession()
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
  }

  func testSkipFocusAfterOneSecondDoesNotCountIt() {
    timer.startTimer()
    runTicks(timer, 1)
    timer.skipSession()
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
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

  // MARK: - Session label

  func testCompletedFocusSessionKeepsItsLabel() {
    defaults.set("  Write report ", forKey: SettingsKey.sessionLabel)
    timer.startTimer()
    finishSession(timer)  // focus
    finishSession(timer)  // short break
    XCTAssertEqual(history.records.map(\.kind), [.focus, .short])
    XCTAssertEqual(history.records.map(\.label), ["Write report", nil])
  }

  func testEmptyLabelIsStoredAsNil() {
    defaults.set("   ", forKey: SettingsKey.sessionLabel)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(history.records.count, 1)
    XCTAssertNil(history.records.first?.label)
  }

  func testSkippedOrResetSessionRecordsNothing() {
    defaults.set("Write report", forKey: SettingsKey.sessionLabel)
    timer.startTimer()
    runTicks(timer, 1)
    timer.stopTimer()
    timer.startTimer()
    timer.skipSession()
    XCTAssertTrue(history.records.isEmpty)
  }

  func testLabelChangedMidSessionDoesNotRelabelTheRunningSession() {
    defaults.set("Write report", forKey: SettingsKey.sessionLabel)
    timer.startTimer()
    runTicks(timer, 1)
    defaults.set("Review code", forKey: SettingsKey.sessionLabel)
    finishSession(timer)
    XCTAssertEqual(history.records.map(\.label), ["Write report"])
  }

  func testLabelTypedAfterStartingWithoutOneLabelsTheRunningSession() {
    defaults.set("   ", forKey: SettingsKey.sessionLabel)
    timer.startTimer()
    XCTAssertEqual(timer.labelCaption, .currentSession)
    defaults.set("Viết báo cáo", forKey: SettingsKey.sessionLabel)
    finishSession(timer)
    XCTAssertEqual(history.records.first?.label, "Viết báo cáo")
  }

  func testLabelEditedInLabelledSessionAppliesFromTheNextSession() {
    defaults.set("A", forKey: SettingsKey.sessionLabel)
    timer.startTimer()
    XCTAssertEqual(timer.labelCaption, .nextSession)
    defaults.set("B", forKey: SettingsKey.sessionLabel)
    finishSession(timer)
    XCTAssertEqual(history.records.last?.label, "A")
    timer.skipSession()
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(history.records.last?.label, "B")
  }

  func testRelaunchOfUnlabelledSessionTakesTheLabelTypedLater() {
    timer = makeTimer(focus: 300)
    timer.startTimer()
    let resumed = relaunch(after: 100)
    XCTAssertEqual(resumed.startedLabel, "")
    defaults.set("Write report", forKey: SettingsKey.sessionLabel)
    finishSession(resumed)
    XCTAssertEqual(history.records.first?.label, "Write report")
  }

  func testLabelCaptionIsIdleBeforeStart() {
    XCTAssertEqual(timer.labelCaption, .idle)
  }

  func testPausedSessionKeepsItsLabelOnResume() {
    defaults.set("Write report", forKey: SettingsKey.sessionLabel)
    timer.startTimer()
    runTicks(timer, 1)
    timer.pauseTimer()
    defaults.set("Review code", forKey: SettingsKey.sessionLabel)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(history.records.first?.label, "Write report")
  }

  func testRelaunchMidSessionKeepsTheStartLabel() {
    timer = makeTimer(focus: 300)
    defaults.set("Write report", forKey: SettingsKey.sessionLabel)
    timer.startTimer()
    defaults.set("Review code", forKey: SettingsKey.sessionLabel)
    _ = relaunch(after: 400)
    XCTAssertEqual(history.records.map(\.label), ["Write report"])
  }

  func testRelaunchMidSessionThenFinishingKeepsTheStartLabel() {
    timer = makeTimer(focus: 300)
    defaults.set("Write report", forKey: SettingsKey.sessionLabel)
    timer.startTimer()
    defaults.set("Review code", forKey: SettingsKey.sessionLabel)
    let resumed = relaunch(after: 100)
    XCTAssertEqual(resumed.startedLabel, "Write report")
    finishSession(resumed)
    XCTAssertEqual(history.records.first?.label, "Write report")
  }

  func testSnapshotWithoutLabelDecodesAndReadsTheFieldLive() throws {
    let old = """
      {"state":"active","sessionType":"Focus","remaining":100,"totalDuration":300,\
      "focusSessionsCompleted":0,"isBreakPostponed":false,"isWaitingToContinue":false,\
      "endDate":0}
      """
    let snapshot = try JSONDecoder().decode(TimerSnapshot.self, from: Data(old.utf8))
    XCTAssertNil(snapshot.label)
    timer = makeTimer(focus: 300)
    timer.startTimer()
    var legacy = TimerSnapshot.load(from: defaults)!
    legacy.label = nil
    legacy.save(to: defaults)
    defaults.set("Typed later", forKey: SettingsKey.sessionLabel)
    _ = relaunch(after: 400)
    XCTAssertEqual(history.records.map(\.label), ["Typed later"])
  }

  func testSessionExpiredWhileClosedKeepsItsLabel() {
    timer = makeTimer(focus: 300)
    defaults.set("Write report", forKey: SettingsKey.sessionLabel)
    timer.startTimer()
    _ = relaunch(after: 400)
    XCTAssertEqual(history.records.map(\.label), ["Write report"])
  }

  func testSettingsResetKeepsTheLabel() {
    defaults.set("Write report", forKey: SettingsKey.sessionLabel)
    SettingsReset.perform(on: defaults, domain: Self.suiteName)
    XCTAssertEqual(defaults.string(forKey: SettingsKey.sessionLabel), "Write report")
  }
}
