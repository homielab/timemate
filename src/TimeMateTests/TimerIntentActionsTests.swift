//  Created by homielab.com

import XCTest

@testable import TimeMate

final class TimerIntentActionsTests: XCTestCase {
  private static let suiteName = "TimeMateIntentTests"

  private var defaults: UserDefaults!
  private var currentTime: Date!
  private var timer: PomodoroTimer!

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
    // Debug builds read minutes as seconds: focus 125 lasts 125 s of the fake clock.
    defaults.set(125, forKey: SettingsKey.focusDuration)
    defaults.set(60, forKey: SettingsKey.shortBreakDuration)
    defaults.set(false, forKey: SettingsKey.notificationsEnabled)
    defaults.set(false, forKey: SettingsKey.autoStartNextSession)
    currentTime = Date(timeIntervalSince1970: 1_000_000)
    timer = PomodoroTimer(
      defaults: defaults, now: { [unowned self] in self.currentTime },
      workspaceNotificationCenter: NotificationCenter(), playSound: { _, _ in },
      isFullscreenProbe: { false })
  }

  override func tearDown() {
    timer.stopTimer()
    timer = nil
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  func testStartStartsAnIdleTimerAndNeverPausesARunningOne() {
    TimerIntentActions.start(timer)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.currentSessionType, .focus)

    TimerIntentActions.start(timer)
    XCTAssertEqual(timer.state, .active)
  }

  func testPauseThenStartResumesWithTheTimeLeft() {
    TimerIntentActions.start(timer)
    currentTime += 20
    timer.handleTick()

    XCTAssertNoThrow(try TimerIntentActions.pause(timer))
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 105)

    TimerIntentActions.start(timer)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 105)
  }

  func testPauseDoesNothingWhenIdle() {
    XCTAssertNoThrow(try TimerIntentActions.pause(timer))
    XCTAssertEqual(timer.state, .idle)
  }

  func testSkipMovesToTheNextSession() {
    TimerIntentActions.start(timer)
    XCTAssertNoThrow(try TimerIntentActions.skip(timer))
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
  }

  func testResetStopsTheTimerAndRestartsTheSession() {
    TimerIntentActions.start(timer)
    currentTime += 20
    timer.handleTick()

    TimerIntentActions.reset(timer)

    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.timeRemaining, 125)
  }

  func testResetClearsAWaitingBreakScreen() {
    timer.currentSessionType = .shortBreak
    timer.isWaitingToContinue = true
    TimerIntentActions.reset(timer)
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.state, .idle)
  }

  func testResetOnAFinishedBreakReturnsToFocus() {
    defaults.set(true, forKey: SettingsKey.keepBreakScreenOpen)
    timer = PomodoroTimer(
      defaults: defaults, now: { [unowned self] in self.currentTime },
      workspaceNotificationCenter: NotificationCenter(), playSound: { _, _ in },
      isFullscreenProbe: { false })
    TimerIntentActions.start(timer)
    currentTime += 125
    timer.handleTick()  // focus ends, the break waits to be started
    TimerIntentActions.start(timer)
    currentTime += 60
    timer.handleTick()  // break ends, waits on the break screen
    XCTAssertTrue(timer.isWaitingToContinue)

    TimerIntentActions.reset(timer)

    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .idle)
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.timeRemaining, 125)
  }

  func testFinishedBreakDoesNotWaitWhileAFullScreenAppHidesTheBreakScreen() {
    defaults.set(true, forKey: SettingsKey.keepBreakScreenOpen)
    defaults.set(true, forKey: SettingsKey.overlaySkipFullscreen)
    timer = PomodoroTimer(
      defaults: defaults, now: { [unowned self] in self.currentTime },
      workspaceNotificationCenter: NotificationCenter(), playSound: { _, _ in },
      isFullscreenProbe: { true })
    XCTAssertFalse(timer.breakScreenCanShow)
    TimerIntentActions.start(timer)
    currentTime += 125
    timer.handleTick()  // focus ends, the break waits to be started
    TimerIntentActions.start(timer)
    currentTime += 60
    timer.handleTick()  // break ends: no break screen to wait on

    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.currentSessionType, .focus)
  }

  func testStartFocusSavesTheLabelAndStarts() {
    TimerIntentActions.startFocus(timer, label: "  Write\nreport  ")

    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(defaults.string(forKey: SettingsKey.sessionLabel), "Write report")
    XCTAssertEqual(timer.sessionLabel(for: .focus), "Write report")
  }

  func testStartFocusCutsALongLabel() {
    TimerIntentActions.startFocus(timer, label: String(repeating: "a", count: 100))
    XCTAssertEqual(
      defaults.string(forKey: SettingsKey.sessionLabel)?.count, SessionLabel.maxLength)
  }

  func testStartFocusWithABlankLabelKeepsTheField() {
    defaults.set("Inbox", forKey: SettingsKey.sessionLabel)
    TimerIntentActions.startFocus(timer, label: "   ")

    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(defaults.string(forKey: SettingsKey.sessionLabel), "Inbox")
    XCTAssertEqual(timer.sessionLabel(for: .focus), "Inbox")
  }

  func testStartFocusLeavesARunningSessionsLabel() {
    TimerIntentActions.startFocus(timer, label: "Design")
    TimerIntentActions.startFocus(timer, label: "Email")

    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(defaults.string(forKey: SettingsKey.sessionLabel), "Design")
    XCTAssertEqual(timer.sessionLabel(for: .focus), "Design")
  }

  func testStartFocusResumesAPausedSessionWithItsLabel() {
    TimerIntentActions.startFocus(timer, label: "Design")
    XCTAssertNoThrow(try TimerIntentActions.pause(timer))
    TimerIntentActions.startFocus(timer, label: "Email")

    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(defaults.string(forKey: SettingsKey.sessionLabel), "Design")
    XCTAssertEqual(timer.sessionLabel(for: .focus), "Design")
  }

  private func finishFocusSession() {
    TimerIntentActions.start(timer)
    while timer.state == .active, timer.currentSessionType == .focus {
      currentTime = currentTime.addingTimeInterval(1)
      timer.handleTick()
    }
  }

  func testStartFocusAfterAFinishedFocusStartsFocusInsteadOfTheBreak() {
    finishFocusSession()
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .idle)

    TimerIntentActions.startFocus(timer, label: "Writing")

    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertEqual(defaults.string(forKey: SettingsKey.sessionLabel), "Writing")
    XCTAssertEqual(timer.sessionLabel(for: .focus), "Writing")
  }

  func testStartFocusWithoutALabelAlsoSkipsTheIdleBreak() {
    finishFocusSession()
    TimerIntentActions.startFocus(timer)

    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
  }

  func testStartStillStartsTheIdleBreak() {
    finishFocusSession()
    TimerIntentActions.start(timer)

    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
  }

  func testStartFocusResumesAPausedBreak() {
    finishFocusSession()
    TimerIntentActions.start(timer)
    XCTAssertNoThrow(try TimerIntentActions.pause(timer))
    TimerIntentActions.startFocus(timer, label: "Writing")

    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
  }

  func testStartFocusContinuesPastAFinishedBreak() {
    finishFocusSession()
    timer.isWaitingToContinue = true
    TimerIntentActions.startFocus(timer, label: "Writing")

    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
    XCTAssertEqual(defaults.string(forKey: SettingsKey.sessionLabel), "Writing")
  }

  func testExtendAddsTimeToARunningSession() {
    TimerIntentActions.start(timer)
    currentTime += 20
    timer.handleTick()

    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 5), .added(5))

    // Debug builds read minutes as seconds.
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 110)
  }

  func testExtendAddsTimeToAPausedSession() {
    TimerIntentActions.start(timer)
    XCTAssertNoThrow(try TimerIntentActions.pause(timer))

    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 10), .added(10))

    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 135)
  }

  func testExtendDoesNothingWhenIdle() {
    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 5), .noSession)
    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(timer.timeRemaining, 125)
  }

  func testExtendDoesNothingDuringAPostponedBreak() {
    XCTAssertNoThrow(try TimerIntentActions.skip(timer))
    TimerIntentActions.start(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    timer.postponeBreak(minutes: 3)
    XCTAssertTrue(timer.isBreakPostponed)
    let endDate = timer.endDate

    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 5), .noSession)
    XCTAssertTrue(timer.isBreakPostponed)
    XCTAssertEqual(timer.endDate, endDate)
  }

  func testExtendReturnsTheMinutesAddedToShortcuts() {
    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 5).minutesAdded, 0, "idle")
    TimerIntentActions.start(timer)
    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 5).minutesAdded, 5)
    TimerIntentActions.extend(timer, minutes: 60)
    TimerIntentActions.extend(timer, minutes: 60)
    let atLimit = TimerIntentActions.extend(timer, minutes: 5)
    XCTAssertEqual(atLimit, .atLimit)
    XCTAssertEqual(atLimit.minutesAdded, 0)
    XCTAssertEqual(TimerIntentActions.extendText(atLimit), "Already at the 180-minute limit")
  }

  func testExtendTextSaysWhatChanged() {
    XCTAssertEqual(TimerIntentActions.extendText(.added(1)), "Added 1 minute")
    XCTAssertEqual(TimerIntentActions.extendText(.added(5)), "Added 5 minutes")
    XCTAssertEqual(TimerIntentActions.extendText(.noSession), "No session to extend")
    XCTAssertEqual(
      TimerIntentActions.extendText(.atLimit), "Already at the 180-minute limit")
  }

  func testExtendStopsAtTheSessionLimit() {
    TimerIntentActions.start(timer)
    XCTAssertNoThrow(try TimerIntentActions.pause(timer))
    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 53), .added(53))
    XCTAssertEqual(timer.timeRemaining, 178)

    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 5), .added(2))
    XCTAssertEqual(timer.timeRemaining, 180)
    XCTAssertTrue(timer.isAtSessionLimit)

    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 5), .atLimit)
    XCTAssertEqual(timer.timeRemaining, 180)
  }

  func testExtendRestartsAFinishedBreak() {
    timer.currentSessionType = .shortBreak
    timer.isWaitingToContinue = true

    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 3), .added(3))

    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 3)
  }

  func testExtendKeepsMinutesWithinOneToSixty() {
    TimerIntentActions.start(timer)
    XCTAssertNoThrow(try TimerIntentActions.pause(timer))

    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 0), .added(1))
    XCTAssertEqual(timer.timeRemaining, 126)
    TimerIntentActions.extend(timer, minutes: -5)
    XCTAssertEqual(timer.timeRemaining, 127)
    // 127 + 60 would pass the 180-minute limit, so only 53 fit.
    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 500), .added(53))
    XCTAssertEqual(timer.timeRemaining, 180)
  }

  func testStartContinuesPastAFinishedBreak() {
    timer.currentSessionType = .shortBreak
    timer.isWaitingToContinue = true
    TimerIntentActions.start(timer)
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
  }

  func testMinutesRemainingRoundsUp() {
    XCTAssertEqual(TimerIntentActions.minutesRemaining(timer), 3)
    TimerIntentActions.start(timer)
    currentTime += 66
    timer.handleTick()
    XCTAssertEqual(timer.timeRemaining, 59)
    XCTAssertEqual(TimerIntentActions.minutesRemaining(timer), 1)
  }

  func testStatusTextNamesTheSessionAndState() {
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Focus, not started, 3 min")
    TimerIntentActions.start(timer)
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Focus, running, 3 min left")
    XCTAssertNoThrow(try TimerIntentActions.pause(timer))
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Focus, paused, 3 min left")
    timer.currentSessionType = .shortBreak
    timer.isWaitingToContinue = true
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Short Break finished")
    XCTAssertEqual(TimerIntentActions.minutesRemaining(timer), 0)
  }

  /// Start, Pause, Skip and Reset answer with `statusText` after they ran.
  func testStatusTextAfterEachCommand() {
    XCTAssertNoThrow(try TimerIntentActions.pause(timer))
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Focus, not started, 3 min")
    TimerIntentActions.start(timer)
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Focus, running, 3 min left")
    XCTAssertNoThrow(try TimerIntentActions.pause(timer))
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Focus, paused, 3 min left")
    TimerIntentActions.reset(timer)
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Focus, not started, 3 min")
    TimerIntentActions.start(timer)
    XCTAssertNoThrow(try TimerIntentActions.skip(timer))
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Short Break, not started, 1 min")
    TimerIntentActions.startFocus(timer)
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Focus, running, 3 min left")
  }

  // MARK: - Today's progress

  private func makeHistory() -> SessionHistory {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return SessionHistory(
      fileURL: nil, now: { [unowned self] in self.currentTime }, calendar: calendar,
      notificationCenter: NotificationCenter())
  }

  func testProgressWithNoSessions() {
    let progress = TimerIntentActions.todayProgress(history: makeHistory(), goal: 0)
    XCTAssertEqual(progress, .init(completed: 0, goal: nil, focusMinutes: 0))
    XCTAssertFalse(progress.goalReached)
    XCTAssertEqual(TimerIntentActions.progressText(progress), "Today: 0 pomodoros · 0 min")
  }

  func testProgressWithoutAGoalCountsOnlyTodaysFocusSessions() {
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 25 * 60, end: currentTime)
    history.recordCompletedSession(.focus, duration: 25 * 60, end: currentTime)
    history.recordCompletedSession(.shortBreak, duration: 5 * 60, end: currentTime)
    history.recordCompletedSession(
      .focus, duration: 25 * 60, end: currentTime.addingTimeInterval(-2 * 86_400))

    let progress = TimerIntentActions.todayProgress(history: history, goal: DailyGoal.off)

    XCTAssertEqual(progress, .init(completed: 2, goal: nil, focusMinutes: 50))
    XCTAssertFalse(progress.goalReached)
    XCTAssertEqual(TimerIntentActions.progressText(progress), "Today: 2 pomodoros · 50 min")
  }

  func testProgressBelowTheGoal() {
    let history = makeHistory()
    for _ in 0..<3 { history.recordCompletedSession(.focus, duration: 25 * 60, end: currentTime) }

    let progress = TimerIntentActions.todayProgress(history: history, goal: 8)

    XCTAssertEqual(progress, .init(completed: 3, goal: 8, focusMinutes: 75))
    XCTAssertFalse(progress.goalReached)
    XCTAssertEqual(
      TimerIntentActions.progressText(progress), "Today: 3 of 8 pomodoros, 75 minutes")
  }

  func testReachingTheGoalSetsGoalReached() {
    let history = makeHistory()
    for _ in 0..<2 { history.recordCompletedSession(.focus, duration: 25 * 60, end: currentTime) }

    XCTAssertTrue(TimerIntentActions.todayProgress(history: history, goal: 2).goalReached)
    history.recordCompletedSession(.focus, duration: 25 * 60, end: currentTime)
    XCTAssertTrue(TimerIntentActions.todayProgress(history: history, goal: 2).goalReached)
    XCTAssertFalse(TimerIntentActions.todayProgress(history: history, goal: 4).goalReached)
  }

  func testProgressTextMentionsTheStreak() {
    let history = makeHistory()
    for day in 0..<3 {
      let end = currentTime.addingTimeInterval(-Double(day) * 86_400)
      history.recordCompletedSession(.focus, duration: 25 * 60, end: end)
    }

    let progress = TimerIntentActions.todayProgress(history: history, goal: 1)

    XCTAssertEqual(progress.streak, 3)
    XCTAssertEqual(
      TimerIntentActions.progressText(progress),
      "Today: 1 of 1 pomodoro, 25 minutes. Streak: 3 days")
    XCTAssertEqual(TimerIntentActions.todayProgress(history: history, goal: 0).streak, 0)
  }

  // MARK: - Break screen skip delay

  /// A running short break whose break screen still blocks skipping for `lock` seconds.
  private func startLockedBreak(lock: Int) {
    TimerIntentActions.start(timer)
    XCTAssertNoThrow(try TimerIntentActions.skip(timer))
    TimerIntentActions.start(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
    timer.breakScreenSkipLock = { lock }
  }

  func testEveryPathIsBlockedWhileTheSkipDelayRuns() {
    startLockedBreak(lock: 9)
    XCTAssertEqual(timer.perform(.skip), "Skip available in 9 s")
    XCTAssertEqual(timer.perform(.startPause), "Skip available in 9 s")
    timer.handleNotificationAction(.skip)
    XCTAssertThrowsError(try TimerIntentActions.skip(timer)) { error in
      XCTAssertEqual(error as? SkipLockedError, SkipLockedError(message: "Skip available in 9 s"))
    }
    XCTAssertThrowsError(try TimerIntentActions.pause(timer))
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
  }

  func testEveryPathWorksOnceTheSkipDelayIsOver() {
    startLockedBreak(lock: 0)
    XCTAssertNil(timer.perform(.startPause))
    XCTAssertEqual(timer.state, .paused)
    timer.perform(.startPause)
    XCTAssertNoThrow(try TimerIntentActions.pause(timer))
    XCTAssertEqual(timer.state, .paused)
    XCTAssertNil(timer.perform(.skip))
    XCTAssertEqual(timer.currentSessionType, .focus)

    startLockedBreak(lock: 0)
    timer.handleNotificationAction(.skip)
    XCTAssertEqual(timer.currentSessionType, .focus)
    startLockedBreak(lock: 0)
    XCTAssertNoThrow(try TimerIntentActions.skip(timer))
    XCTAssertEqual(timer.currentSessionType, .focus)
  }

  func testTheLockDoesNotApplyToFocusSessions() {
    TimerIntentActions.start(timer)
    timer.breakScreenSkipLock = { 9 }
    XCTAssertEqual(timer.skipLockSeconds, 0)
    XCTAssertNil(timer.perform(.skip))
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
  }
}
