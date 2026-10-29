//  Created by homielab.com

import XCTest

@testable import TimeMate

/// "Auto-pause when I'm away" on `PomodoroTimer`, with a fake idle clock
/// (`idleTime`) and the idle checks collected by `TimerTestCase`.
final class PomodoroTimerIdleTests: TimerTestCase {
  /// Debug builds count minutes as seconds: 10 "minutes" away = 10 s.
  private let awayMinutes = 10
  private var threshold: TimeInterval {
    TimeInterval(PomodoroTimer.seconds(forMinutes: awayMinutes))
  }

  /// A focus timer with "Auto-pause when I'm away" on, 20 s into its session.
  private func makeRunningTimer(focus: Int = 120, resumeOnReturn: Bool = false) {
    defaults.set(awayMinutes, forKey: SettingsKey.idlePauseMinutes)
    defaults.set(resumeOnReturn, forKey: SettingsKey.resumeOnReturn)
    timer = makeTimer(focus: focus)
    timer.startTimer()
    runTicks(timer, 20)
  }

  /// One tick `seconds` later, the user away the whole time.
  private func tickAway(_ seconds: TimeInterval) {
    advanceClock(by: seconds)
    idleTime += seconds
    timer.handleTick()
  }

  func testAwayPausesTheFocusSessionAndGivesBackTheTimeAway() {
    makeRunningTimer()
    XCTAssertEqual(timer.timeRemaining, 100)
    tickAway(15)
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 100)
    XCTAssertTrue(timer.pausedBySleep)
    XCTAssertTrue(history.records.isEmpty)
  }

  func testMeetingOrVideoKeepsTheSessionRunning() {
    makeRunningTimer()
    displayKeptAwake = true
    tickAway(threshold + 5)
    XCTAssertEqual(timer.state, .active)
    XCTAssertFalse(timer.pausedBySleep)
    runIdleCheck()
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(idleChecks.first?.delay, IdlePausePolicy.keptAwakeCheckInterval)
    displayKeptAwake = false
    runIdleCheck()
    XCTAssertEqual(timer.state, .paused)
  }

  func testShortIdleKeepsCounting() {
    makeRunningTimer()
    tickAway(threshold - 1)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 100 - Int(threshold - 1))
  }

  func testOffChangesNothing() {
    timer = makeTimer(focus: 30)
    timer.startTimer()
    XCTAssertTrue(idleChecks.isEmpty)
    idleTime = 10_000
    finishSession(timer)
    XCTAssertEqual(history.records.count, 1)
    XCTAssertEqual(history.records.first?.kind, .focus)
    XCTAssertTrue(idleChecks.isEmpty)
  }

  func testAwayAtTheEndPausesInsteadOfRecordingTheSession() {
    makeRunningTimer(focus: 30)
    runTicks(timer, 9)
    // The end tick comes 1 s later; the user left 12 s before it, with 12 s to go.
    idleTime = 11
    tickAway(1)
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 12)
    XCTAssertTrue(history.records.isEmpty)
  }

  func testBreakKeepsRunningWhileAway() {
    makeRunningTimer(focus: 30)
    runTicks(timer, 10)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertTrue(idleChecks.isEmpty)
    idleTime = 1000
    finishSession(timer)
    XCTAssertEqual(history.records.map(\.kind), [.focus, .short])
    // Focus started by itself while the user is away: it pauses at once, whole.
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(idleChecks.first?.delay, IdlePausePolicy.minimumCheckDelay)
    runIdleCheck()
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 30)
  }

  func testIdleCheckRunsWhenTheThresholdCanFirstBeReached() {
    makeRunningTimer()
    XCTAssertEqual(idleChecks.map(\.delay), [threshold])
    // Input came in meanwhile: still running, next check a full threshold later.
    runIdleCheck(away: false)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 100 - Int(threshold))
    idleTime = 4
    timer.updateIdleWatch()
    XCTAssertEqual(idleChecks.map(\.delay), [threshold - 4])
    runIdleCheck()
    XCTAssertEqual(timer.state, .paused)
    // 100 - 10 - 6 = 84 left, plus the 10 s away.
    XCTAssertEqual(timer.timeRemaining, 94)
  }

  func testGivesBackNoMoreThanTheSessionRanSinceItResumed() {
    makeRunningTimer()
    timer.pauseTimer()
    advanceClock(by: 600)
    timer.startTimer()
    runTicks(timer, 3)
    tickAway(1)
    idleTime = 1000
    tickAway(1)
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 100)
  }

  func testResumeWhenBackContinuesOnInput() {
    makeRunningTimer(resumeOnReturn: true)
    runIdleCheck()
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(timer.timeRemaining, 100)
    XCTAssertEqual(idleChecks.map(\.delay), [IdlePausePolicy.returnCheckInterval])
    // Still away: keeps looking.
    runIdleCheck()
    XCTAssertEqual(timer.state, .paused)
    XCTAssertEqual(idleChecks.count, 1)
    XCTAssertTrue(scheduledResumes.isEmpty)
    // A key press: continues a moment later, like after an unlock.
    idleTime = 0.5
    runIdleCheck(away: false)
    XCTAssertEqual(scheduledResumes.map(\.delay), [PomodoroTimer.resumeDelay])
    runScheduledResumes()
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, 100)
    XCTAssertEqual(idleChecks.map(\.delay), [threshold - 0.5])
  }

  func testWithoutResumeWhenBackTheSessionStaysPaused() {
    makeRunningTimer()
    runIdleCheck()
    XCTAssertEqual(timer.state, .paused)
    XCTAssertTrue(idleChecks.isEmpty)
  }

  func testResumeWhenBackLeavesASessionPausedByTheUser() {
    makeRunningTimer(resumeOnReturn: true)
    timer.pauseTimer()
    XCTAssertTrue(idleChecks.isEmpty)
    XCTAssertFalse(timer.pausedBySleep)
  }

  func testUnlockAlsoResumesASessionPausedWhileAway() {
    makeRunningTimer(resumeOnReturn: true)
    runIdleCheck()
    XCTAssertEqual(timer.state, .paused)
    distributedCenter.post(
      name: Notification.Name(PomodoroTimer.screenUnlockedNotificationName), object: nil)
    runScheduledResumes()
    XCTAssertEqual(timer.state, .active)
  }

  func testTurningTheSettingOnOrOffWhileRunning() {
    timer = makeTimer(focus: 120)
    timer.startTimer()
    XCTAssertTrue(idleChecks.isEmpty)
    defaults.set(awayMinutes, forKey: SettingsKey.idlePauseMinutes)
    XCTAssertTrue(waitUntil { !self.idleChecks.isEmpty })
    defaults.set(IdlePausePolicy.off, forKey: SettingsKey.idlePauseMinutes)
    XCTAssertTrue(waitUntil { self.idleChecks.isEmpty })
  }
}
