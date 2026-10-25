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
      workspaceNotificationCenter: NotificationCenter())
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
}
