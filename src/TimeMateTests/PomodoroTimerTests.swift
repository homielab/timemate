//  Created by homielab.com

import AppKit
import XCTest

@testable import TimeMate

final class PomodoroTimerTests: XCTestCase {
  private static let suiteName = "TimeMateTests"

  private var defaults: UserDefaults!
  private var currentTime: Date!
  private var workspaceCenter: NotificationCenter!
  private var clockCenter: NotificationCenter!
  private var distributedCenter: NotificationCenter!
  /// The fake `uptime` clock: moves with real time, not with clock changes.
  private var currentUptime: TimeInterval = 0
  private var history: SessionHistory!
  private var timer: PomodoroTimer!

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
    currentTime = Date(timeIntervalSince1970: 1_000_000)
    workspaceCenter = NotificationCenter()
    clockCenter = NotificationCenter()
    distributedCenter = NotificationCenter()
    currentUptime = 50_000
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
      distributedNotificationCenter: distributedCenter,
      history: history,
      notificationCenter: clockCenter,
      uptime: { [weak self] in self?.currentUptime ?? 0 })
  }

  /// Advances the fake clock one second per tick, like the real 1 s timer.
  private func runTicks(_ timer: PomodoroTimer, _ count: Int) {
    for _ in 0..<count {
      advanceClock(by: 1)
      timer.handleTick()
    }
  }

  /// Lets `seconds` of real time pass.
  private func advanceClock(by seconds: TimeInterval) {
    currentTime = currentTime.addingTimeInterval(seconds)
    currentUptime += seconds
  }

  /// Sets the system time forward (or back) by `seconds`; no time passes.
  private func setSystemClock(by seconds: TimeInterval) {
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

  // MARK: - Pause on sleep or screen lock

  private func lockScreen() {
    distributedCenter.post(
      name: Notification.Name(PomodoroTimer.screenLockedNotificationName), object: nil)
  }

  func testPauseOnSleepOffKeepsCountingThroughSleep() {
    timer = makeTimer(focus: 120)
    timer.startTimer()
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    lockScreen()
    workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    XCTAssertEqual(timer.state, .active)
    advanceClock(by: 60)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 60)
  }

  func testPauseOnSleepKeepsSessionPausedAfterLongSleep() {
    defaults.set(true, forKey: SettingsKey.pauseOnSleep)
    timer = makeTimer(focus: 3000)
    timer.startTimer()
    runTicks(timer, 20)
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    XCTAssertEqual(timer.state, .paused)
    advanceClock(by: 40 * 60)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 2980)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertTrue(history.records.isEmpty)
    XCTAssertEqual(timer.focusSessionsCompleted, 0)
  }

  func testPauseOnSleepPausesWhenScreenLocksOrSleeps() {
    defaults.set(true, forKey: SettingsKey.pauseOnSleep)
    timer = makeTimer(focus: 120)
    timer.startTimer()
    lockScreen()
    XCTAssertEqual(timer.state, .paused)
    timer.startTimer()
    XCTAssertEqual(timer.state, .active)
    workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    XCTAssertEqual(timer.state, .paused)
  }

  func testPauseOnSleepLeavesIdleTimerAlone() {
    defaults.set(true, forKey: SettingsKey.pauseOnSleep)
    lockScreen()
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    XCTAssertEqual(timer.state, .idle)
  }

  func testPausedBySleepSurvivesRelaunch() {
    defaults.set(true, forKey: SettingsKey.pauseOnSleep)
    timer = makeTimer(focus: 120)
    timer.startTimer()
    runTicks(timer, 20)
    lockScreen()
    advanceClock(by: 3600)
    let relaunched = makeTimer(focus: 120)
    XCTAssertEqual(relaunched.state, .paused)
    XCTAssertEqual(relaunched.timeRemaining, 100)
  }

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

  // MARK: - Extend and postpone a break

  /// Five minutes of session time (seconds-as-minutes in Debug builds).
  private var fiveMinutes: TimeInterval {
    TimeInterval(PomodoroTimer.seconds(forMinutes: 5))
  }

  private func startShortBreak() {
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
  }

  func testSecondsForMinutesMatchesTheBuild() {
    #if DEBUG
      XCTAssertEqual(PomodoroTimer.seconds(forMinutes: 5), 5)
    #else
      XCTAssertEqual(PomodoroTimer.seconds(forMinutes: 5), 300)
    #endif
  }

  func testExtendPushesEndDateOfRunningBreakByFiveMinutes() {
    startShortBreak()
    let endDate = timer.endDate!
    timer.extend(by: 5)
    XCTAssertEqual(timer.endDate, endDate.addingTimeInterval(fiveMinutes))
    XCTAssertEqual(timer.timeRemaining, 2 + Int(fiveMinutes))
    XCTAssertEqual(timer.progress, 1.0)
    XCTAssertEqual(timer.state, .active)
  }

  func testExtendedBreakEndsAtTheNewEndDate() {
    startShortBreak()
    timer.extend(by: 5)
    runTicks(timer, 2 + Int(fiveMinutes) - 1)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    runTicks(timer, 1)
    XCTAssertEqual(timer.currentSessionType, .focus)
  }

  func testExtendWhilePausedAddsToRemainingTime() {
    startShortBreak()
    timer.pauseTimer()
    timer.extend(by: 5)
    XCTAssertEqual(timer.timeRemaining, 2 + Int(fiveMinutes))
    XCTAssertNil(timer.endDate)
    timer.startTimer()
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(2 + fiveMinutes))
  }

  func testExtendDoesNothingDuringFocus() {
    timer.startTimer()
    let endDate = timer.endDate
    timer.extend(by: 5)
    XCTAssertEqual(timer.endDate, endDate)
    XCTAssertEqual(timer.timeRemaining, 3)
  }

  func testExtendOnWaitingBreakScreenStartsFiveMoreMinutes() {
    timer = makeTimer(keepBreakOpen: true)
    startShortBreak()
    finishSession(timer)
    XCTAssertTrue(timer.isWaitingToContinue)
    timer.extend(by: 5)
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(fiveMinutes))
  }

  func testPostponeHidesBreakAndBringsItBackOnTime() {
    startShortBreak()
    timer.postponeBreak(minutes: 3)
    let delay = PomodoroTimer.seconds(forMinutes: 3)
    XCTAssertTrue(timer.isBreakPostponed)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(TimeInterval(delay)))

    runTicks(timer, delay - 1)
    XCTAssertTrue(timer.isBreakPostponed)
    runTicks(timer, 1)
    // The break is back at its full length, not finished or skipped.
    XCTAssertFalse(timer.isBreakPostponed)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 2)
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(2))
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertEqual(history.records.count, 1)  // only the focus session

    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(history.records.count, 2)
  }

  func testPostponedBreakReturnsAfterSleep() {
    startShortBreak()
    timer.postponeBreak(minutes: 1)
    workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    advanceClock(by: 600)
    workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertFalse(timer.isBreakPostponed)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.timeRemaining, 2)
  }

  func testPostponeOnlyWorksDuringARunningBreak() {
    timer.startTimer()
    timer.postponeBreak(minutes: 1)
    XCTAssertFalse(timer.isBreakPostponed)

    finishSession(timer)
    timer.pauseTimer()
    timer.postponeBreak(minutes: 1)
    XCTAssertFalse(timer.isBreakPostponed)
  }

  func testSkipDuringPostponedBreakGoesToFocus() {
    startShortBreak()
    timer.postponeBreak(minutes: 5)
    timer.skipSession()
    XCTAssertFalse(timer.isBreakPostponed)
    XCTAssertEqual(timer.currentSessionType, .focus)
  }

  func testExtendIsIgnoredWhileBreakIsPostponed() {
    startShortBreak()
    timer.postponeBreak(minutes: 1)
    let endDate = timer.endDate
    timer.extend(by: 5)
    XCTAssertEqual(timer.endDate, endDate)
  }

  // MARK: - Relaunch

  /// Drops the running timer and builds a new one from the same defaults and
  /// clock, as when the app quits and opens again.
  private func relaunch(
    after seconds: TimeInterval, focus: Int = 300, autoStart: Bool = true,
    keepBreakOpen: Bool = false
  ) -> PomodoroTimer {
    timer = nil
    advanceClock(by: seconds)
    return makeTimer(focus: focus, autoStart: autoStart, keepBreakOpen: keepBreakOpen)
  }

  func testRunningSessionKeepsCountingAfterRelaunch() {
    timer = makeTimer(focus: 300)
    timer.startTimer()
    let endDate = timer.endDate

    let relaunched = relaunch(after: 120)
    XCTAssertEqual(relaunched.state, .active)
    XCTAssertEqual(relaunched.currentSessionType, .focus)
    XCTAssertEqual(relaunched.endDate, endDate)
    XCTAssertEqual(relaunched.timeRemaining, 180)
    XCTAssertEqual(relaunched.progress, 0.6, accuracy: 0.001)
    XCTAssertTrue(history.records.isEmpty)
  }

  func testPausedSessionStaysPausedAfterRelaunch() {
    timer = makeTimer(focus: 3, short: 2, interval: 4)
    timer.startTimer()
    finishSession(timer)  // one focus done, short break running
    timer.skipSession()  // focus again
    runTicks(timer, 1)
    timer.pauseTimer()

    let relaunched = relaunch(after: 600, focus: 3)
    XCTAssertEqual(relaunched.state, .paused)
    XCTAssertNil(relaunched.endDate)
    XCTAssertEqual(relaunched.timeRemaining, 2)
    XCTAssertEqual(relaunched.focusSessionsCompleted, 1)

    relaunched.startTimer()
    XCTAssertEqual(relaunched.timeRemaining, 2)
    XCTAssertEqual(relaunched.state, .active)
  }

  func testSessionThatEndedWhileClosedIsRecordedAndNextSessionWaits() {
    timer = makeTimer(focus: 300, autoStart: false)
    timer.startTimer()
    let endDate = timer.endDate!

    let relaunched = relaunch(after: 3 * 3600, autoStart: false)
    XCTAssertEqual(history.records.count, 1)
    XCTAssertEqual(history.records.first?.kind, .focus)
    XCTAssertEqual(history.records.first?.end, endDate)
    XCTAssertEqual(history.records.first?.duration, 300)
    XCTAssertEqual(relaunched.currentSessionType, .shortBreak)
    XCTAssertEqual(relaunched.focusSessionsCompleted, 1)
    XCTAssertEqual(relaunched.state, .idle)
    XCTAssertEqual(relaunched.timeRemaining, 2)
  }

  func testSessionThatEndedWhileClosedStartsNextWhenAutoStartIsOn() {
    timer = makeTimer(focus: 300)
    timer.startTimer()

    let relaunched = relaunch(after: 3600)
    XCTAssertEqual(history.records.count, 1)
    XCTAssertEqual(relaunched.currentSessionType, .shortBreak)
    XCTAssertEqual(relaunched.state, .active)
    XCTAssertEqual(relaunched.endDate, currentTime.addingTimeInterval(2))
  }

  func testBreakThatEndedWhileClosedDoesNotOpenBreakScreen() {
    timer = makeTimer(focus: 3, short: 60, keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)

    let relaunched = relaunch(after: 3600, focus: 3, keepBreakOpen: true)
    XCTAssertEqual(history.records.count, 2)
    XCTAssertFalse(relaunched.isWaitingToContinue)
    XCTAssertEqual(relaunched.currentSessionType, .focus)
    XCTAssertEqual(relaunched.state, .idle)
  }

  func testWaitingBreakScreenMovesToNextSessionAfterRelaunch() {
    timer = makeTimer(focus: 3, short: 2, keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    finishSession(timer)
    XCTAssertTrue(timer.isWaitingToContinue)

    let relaunched = relaunch(after: 60, focus: 3, keepBreakOpen: true)
    XCTAssertFalse(relaunched.isWaitingToContinue)
    XCTAssertEqual(relaunched.currentSessionType, .focus)
    XCTAssertEqual(relaunched.state, .idle)
    XCTAssertEqual(relaunched.focusSessionsCompleted, 1)
    XCTAssertEqual(history.records.count, 2)
  }

  func testPostponedBreakSurvivesRelaunch() {
    timer = makeTimer(focus: 3, short: 2)
    timer.startTimer()
    finishSession(timer)
    timer.postponeBreak(minutes: 10)

    let relaunched = relaunch(after: 4, focus: 3)
    XCTAssertTrue(relaunched.isBreakPostponed)
    XCTAssertEqual(relaunched.state, .active)
    XCTAssertEqual(relaunched.timeRemaining, 6)

    let due = relaunch(after: 60, focus: 3)
    XCTAssertFalse(due.isBreakPostponed)
    XCTAssertEqual(due.currentSessionType, .shortBreak)
    XCTAssertEqual(due.state, .idle)
    XCTAssertEqual(due.timeRemaining, 2)
    XCTAssertEqual(history.records.count, 1)
  }

  func testDamagedSnapshotIsIgnored() {
    for damaged: Any in [
      Data("not json".utf8), "text",
      try! JSONEncoder().encode(
        TimerSnapshot(
          state: .active, sessionType: .focus, endDate: nil, remaining: 5,
          totalDuration: 10, focusSessionsCompleted: 2, isBreakPostponed: false,
          isWaitingToContinue: false)),
    ] {
      timer = nil
      defaults.set(damaged, forKey: SettingsKey.timerSnapshot)
      timer = makeTimer()
      XCTAssertEqual(timer.state, .idle)
      XCTAssertEqual(timer.currentSessionType, .focus)
      XCTAssertEqual(timer.focusSessionsCompleted, 0)
      XCTAssertEqual(timer.timeRemaining, 3)
      XCTAssertNotNil(TimerSnapshot.load(from: defaults))
    }
  }

  func testClockSetBackCannotStretchRestoredSession() {
    timer = makeTimer(focus: 300)
    timer.startTimer()

    let relaunched = relaunch(after: -3600)
    XCTAssertEqual(relaunched.state, .active)
    XCTAssertEqual(relaunched.timeRemaining, 300)
  }

  // MARK: - System clock changes

  func testClockSetForwardKeepsTheRemainingTime() {
    timer = makeTimer(focus: 600)
    timer.startTimer()
    runTicks(timer, 10)
    setSystemClock(by: 3600)
    timer.handleSystemClockChange()
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.timeRemaining, 590)
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(590))
    XCTAssertTrue(history.records.isEmpty)
  }

  func testClockSetBackDoesNotStretchTheSession() {
    timer = makeTimer(focus: 600)
    timer.startTimer()
    runTicks(timer, 10)
    setSystemClock(by: -7200)
    timer.handleSystemClockChange()
    XCTAssertEqual(timer.timeRemaining, 590)
    runTicks(timer, 590)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
  }

  func testClockChangeIsSavedForTheNextLaunch() {
    timer = makeTimer(focus: 600)
    timer.startTimer()
    setSystemClock(by: 3600)
    timer.handleSystemClockChange()
    let relaunched = relaunch(after: 100, focus: 600)
    XCTAssertEqual(relaunched.state, .active)
    XCTAssertEqual(relaunched.timeRemaining, 500)
  }

  func testClockChangeWhilePausedKeepsThePausedTime() {
    timer = makeTimer(focus: 600)
    timer.startTimer()
    runTicks(timer, 10)
    timer.pauseTimer()
    setSystemClock(by: 3600)
    timer.handleSystemClockChange()
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 590)
  }

  func testPostedClockChangeNotificationMovesTheEndDate() {
    timer = makeTimer(focus: 600)
    timer.startTimer()
    setSystemClock(by: 3600)
    clockCenter.post(name: .NSSystemClockDidChange, object: nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    XCTAssertEqual(timer.endDate, currentTime.addingTimeInterval(600))
  }

  // MARK: - Tick mode

  func testAtEndModeSkipsSecondTicksAndCatchesUpWhenShownAgain() {
    timer = makeTimer(focus: 600)
    timer.startTimer()
    timer.tickMode = .atEnd
    advanceClock(by: 100)
    XCTAssertEqual(timer.timeRemaining, 600)
    XCTAssertEqual(timer.secondsRemaining, 500)
    XCTAssertEqual(TimerIntentActions.minutesRemaining(timer), 9)
    timer.tickMode = .everySecond
    XCTAssertEqual(timer.timeRemaining, 500)
  }

  func testSwitchingTickModeAfterTheEndFinishesTheSessionOnce() {
    timer = makeTimer(focus: 3, autoStart: false)
    timer.startTimer()
    timer.tickMode = .atEnd
    advanceClock(by: 10)
    timer.tickMode = .everySecond
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(history.records.count, 1)
  }

  func testAtEndModeFinishesTheSessionAtItsEnd() {
    timer = makeTimer(focus: 1, autoStart: false)
    timer.tickMode = .atEnd
    timer.startTimer()
    advanceClock(by: 1)
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(history.records.count, 1)
  }
}
