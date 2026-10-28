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
      workspaceNotificationCenter: NotificationCenter(), isFullscreenProbe: { false })
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

    TimerIntentActions.pause(timer)
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 105)

    TimerIntentActions.start(timer)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 105)
  }

  func testPauseDoesNothingWhenIdle() {
    TimerIntentActions.pause(timer)
    XCTAssertEqual(timer.state, .idle)
  }

  func testSkipMovesToTheNextSession() {
    TimerIntentActions.start(timer)
    TimerIntentActions.skip(timer)
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
      workspaceNotificationCenter: NotificationCenter(), isFullscreenProbe: { false })
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
      workspaceNotificationCenter: NotificationCenter(), isFullscreenProbe: { true })
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
    TimerIntentActions.pause(timer)
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
    TimerIntentActions.pause(timer)
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

    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 5), 5)

    // Debug builds read minutes as seconds.
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 110)
  }

  func testExtendAddsTimeToAPausedSession() {
    TimerIntentActions.start(timer)
    TimerIntentActions.pause(timer)

    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 10), 10)

    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 135)
  }

  func testExtendDoesNothingWhenIdle() {
    XCTAssertNil(TimerIntentActions.extend(timer, minutes: 5))
    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(timer.timeRemaining, 125)
  }

  func testExtendDoesNothingDuringAPostponedBreak() {
    TimerIntentActions.skip(timer)
    TimerIntentActions.start(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    timer.postponeBreak(minutes: 3)
    XCTAssertTrue(timer.isBreakPostponed)
    let endDate = timer.endDate

    XCTAssertNil(TimerIntentActions.extend(timer, minutes: 5))
    XCTAssertTrue(timer.isBreakPostponed)
    XCTAssertEqual(timer.endDate, endDate)
  }

  func testExtendTextSaysWhatChanged() {
    XCTAssertEqual(TimerIntentActions.extendText(added: 1), "Added 1 minute")
    XCTAssertEqual(TimerIntentActions.extendText(added: 5), "Added 5 minutes")
    XCTAssertEqual(TimerIntentActions.extendText(added: nil), "No session to extend")
  }

  func testExtendRestartsAFinishedBreak() {
    timer.currentSessionType = .shortBreak
    timer.isWaitingToContinue = true

    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 3), 3)

    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 3)
  }

  func testExtendKeepsMinutesWithinOneToSixty() {
    TimerIntentActions.start(timer)
    TimerIntentActions.pause(timer)

    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 0), 1)
    XCTAssertEqual(timer.timeRemaining, 126)
    TimerIntentActions.extend(timer, minutes: -5)
    XCTAssertEqual(timer.timeRemaining, 127)
    XCTAssertEqual(TimerIntentActions.extend(timer, minutes: 500), 60)
    XCTAssertEqual(timer.timeRemaining, 187)
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
    TimerIntentActions.pause(timer)
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Focus, paused, 3 min left")
    timer.currentSessionType = .shortBreak
    timer.isWaitingToContinue = true
    XCTAssertEqual(TimerIntentActions.statusText(timer), "Short Break finished")
    XCTAssertEqual(TimerIntentActions.minutesRemaining(timer), 0)
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
}
