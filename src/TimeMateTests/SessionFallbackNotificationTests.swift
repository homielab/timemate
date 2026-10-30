//  Created by homielab.com

import UserNotifications
import XCTest

@testable import TimeMate

/// The scheduled copy of the "session complete" notification that still shows
/// when the app quits, crashes or is late at the end of a session.
final class SessionFallbackNotificationTests: TimerTestCase {
  /// A stand-in for `UNUserNotificationCenter`: pending and shown requests by
  /// identifier, a new request replacing the pending one with the same identifier.
  final class FakeCenter {
    var pending: [String: UNNotificationRequest] = [:]
    var shown: [UNNotificationRequest] = []
    /// Every request added, shown or scheduled.
    var addCount = 0

    func add(_ request: UNNotificationRequest) {
      addCount += 1
      if request.trigger == nil {
        pending[request.identifier] = nil
        shown.append(request)
      } else {
        pending[request.identifier] = request
      }
    }

    func removePending() {
      pending[SessionNotification.sessionCompleteIdentifier] = nil
    }

    func removeAll() {
      removePending()
    }

    var sessionPending: UNNotificationRequest? {
      pending[SessionNotification.sessionCompleteIdentifier]
    }

    /// Seconds from `now` until the pending copy fires.
    var pendingInterval: TimeInterval? {
      (sessionPending?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval
    }
  }

  var center: FakeCenter!

  override func setUp() {
    super.setUp()
    center = FakeCenter()
    timer = makeNotifyingTimer()
  }

  /// Focus 3 s, short break 2 s (Debug: minutes are seconds), notifications on.
  func makeNotifyingTimer(autoStart: Bool = true, focus: Int = 3) -> PomodoroTimer {
    defaults.set(focus, forKey: SettingsKey.focusDuration)
    defaults.set(2, forKey: SettingsKey.shortBreakDuration)
    defaults.set(4, forKey: SettingsKey.longBreakDuration)
    defaults.set(4, forKey: SettingsKey.longBreakInterval)
    defaults.set(autoStart, forKey: SettingsKey.autoStartNextSession)
    defaults.set(false, forKey: SettingsKey.keepBreakScreenOpen)
    defaults.set(true, forKey: SettingsKey.notificationsEnabled)
    defaults.set(0.0, forKey: SettingsKey.alarmVolume)
    return PomodoroTimer(
      defaults: defaults,
      now: { [weak self] in self?.currentTime ?? Date(timeIntervalSince1970: 0) },
      workspaceNotificationCenter: workspaceCenter,
      distributedNotificationCenter: distributedCenter,
      history: history,
      notificationCenter: clockCenter,
      uptime: { [weak self] in self?.currentUptime ?? 0 },
      postNotification: { [weak self] in self?.center.add($0) },
      removeSessionNotifications: { [weak self] in self?.center.removeAll() },
      removePendingSessionNotification: { [weak self] in self?.center.removePending() },
      playSound: { _, _ in },
      isFullscreenProbe: { false })
  }

  private var delay: TimeInterval { SessionNotification.fallbackDelay }

  func testStartSchedulesOneCopyAtTheEnd() {
    timer.startTimer()
    XCTAssertEqual(center.pending.count, 1)
    XCTAssertEqual(center.pendingInterval, 3 + delay)
    XCTAssertTrue(center.shown.isEmpty)
    let content = center.sessionPending?.content
    XCTAssertEqual(content?.categoryIdentifier, SessionNotification.autoStartedCategoryIdentifier)
    XCTAssertEqual(
      content?.body,
      SessionNotification.body(next: .shortBreak, minutes: 2, autoStarted: true))
  }

  func testPauseStopSkipResetCancelTheCopy() {
    for action: (PomodoroTimer) -> Void in [
      { $0.pauseTimer() }, { $0.stopTimer() }, { $0.skipSession() }, { $0.restartCycle() },
    ] {
      timer = makeNotifyingTimer(autoStart: false)
      timer.startTimer()
      XCTAssertNotNil(center.sessionPending)
      action(timer)
      XCTAssertNil(center.sessionPending)
      XCTAssertTrue(center.shown.isEmpty)
    }
  }

  func testResumeSchedulesTheCopyForTheNewEnd() {
    timer.startTimer()
    advanceClock(by: 1)
    timer.pauseTimer()
    advanceClock(by: 60)
    timer.startTimer()
    XCTAssertEqual(center.pending.count, 1)
    XCTAssertEqual(center.pendingInterval, 2 + delay)
  }

  func testExtendMovesTheCopy() {
    timer.startTimer()
    timer.extend(by: 5)
    XCTAssertEqual(center.pending.count, 1)
    XCTAssertEqual(center.pendingInterval, 8 + delay)
  }

  func testPostponedBreakHasNoCopyUntilTheBreakComesBack() {
    timer = makeNotifyingTimer(autoStart: true)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    timer.postponeBreak(minutes: 4)
    XCTAssertNil(center.sessionPending)
    runTicks(timer, 4)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(center.pendingInterval, 2 + delay)
  }

  func testClockChangeKeepsTheCopyOnTheSessionsEnd() {
    timer.startTimer()
    setSystemClock(by: 3600)
    clockCenter.post(name: .NSSystemClockDidChange, object: nil)
    XCTAssertTrue(waitUntil { self.timer.endDate == self.currentTime.addingTimeInterval(3) })
    XCTAssertEqual(center.pendingInterval, 3 + delay)
  }

  func testOnTimeEndPostsOnceAndReplacesTheCopy() {
    timer = makeNotifyingTimer(autoStart: false)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(center.shown.count, 1)
    XCTAssertEqual(center.shown.first?.identifier, SessionNotification.sessionCompleteIdentifier)
    XCTAssertNil(center.sessionPending)
  }

  func testAutoStartedSessionGetsItsOwnCopy() {
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(center.shown.count, 1)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(center.pending.count, 1)
    XCTAssertEqual(center.pendingInterval, 2 + delay)
  }

  func testLateEndAfterTheCopyShowedDoesNotPostAgain() {
    timer.startTimer()
    // The Mac slept through the end; the copy showed while the app was late.
    advanceClock(by: 3 + delay + 30)
    timer.handleDidWake()
    XCTAssertTrue(center.shown.isEmpty, "the scheduled copy has already shown")
    XCTAssertEqual(history.todayTotals().pomodoros, 1)
    XCTAssertEqual(center.pendingInterval, 2 + delay, "the next session gets its copy")
  }

  func testSlightlyLateTickStillPostsOnTime() {
    timer.startTimer()
    advanceClock(by: 3 + delay - 1)
    timer.handleTick()
    XCTAssertEqual(center.shown.count, 1)
  }

  func testTurningNotificationsOffCancelsTheCopy() {
    timer.startTimer()
    defaults.set(false, forKey: SettingsKey.notificationsEnabled)
    timer.handleDefaultsChange()
    XCTAssertNil(center.sessionPending)
    defaults.set(true, forKey: SettingsKey.notificationsEnabled)
    timer.handleDefaultsChange()
    XCTAssertEqual(center.pendingInterval, 3 + delay)
  }

  func testNoCopyWhenNotificationsAreOff() {
    defaults.set(false, forKey: SettingsKey.notificationsEnabled)
    timer.startTimer()
    XCTAssertNil(center.sessionPending)
  }

  // MARK: - Settings changed mid-session

  func testTurningAutoStartOnSchedulesTheCopyAgain() {
    timer = makeNotifyingTimer(autoStart: false)
    timer.startTimer()
    XCTAssertEqual(
      center.sessionPending?.content.categoryIdentifier, SessionNotification.categoryIdentifier)
    let added = center.addCount
    defaults.set(true, forKey: SettingsKey.autoStartNextSession)
    timer.handleDefaultsChange()
    XCTAssertEqual(center.addCount, added + 1)
    let content = center.sessionPending?.content
    XCTAssertEqual(content?.categoryIdentifier, SessionNotification.autoStartedCategoryIdentifier)
    XCTAssertEqual(
      content?.body, SessionNotification.body(next: .shortBreak, minutes: 2, autoStarted: true))
    XCTAssertEqual(center.pendingInterval, 3 + delay, "still due at the session's end")
  }

  func testChangingTheNextSessionsLengthUpdatesTheCopy() {
    timer.startTimer()
    advanceClock(by: 1)
    defaults.set(7, forKey: SettingsKey.shortBreakDuration)
    timer.handleDefaultsChange()
    XCTAssertEqual(
      center.sessionPending?.content.body,
      SessionNotification.body(next: .shortBreak, minutes: 7, autoStarted: true))
    XCTAssertEqual(center.pendingInterval, 2 + delay)
  }

  func testChangingTheLongBreakIntervalUpdatesTheCopy() {
    timer.startTimer()
    finishSession(timer)  // focus -> short break
    finishSession(timer)  // short break -> second focus
    defaults.set(2, forKey: SettingsKey.longBreakInterval)
    timer.handleDefaultsChange()
    XCTAssertEqual(
      center.sessionPending?.content.body,
      SessionNotification.body(next: .longBreak, minutes: 4, autoStarted: true))
  }

  func testUnchangedSettingsDoNotScheduleAgain() {
    timer.startTimer()
    let added = center.addCount
    defaults.set(3, forKey: SettingsKey.focusDuration)
    timer.handleDefaultsChange()
    timer.handleDefaultsChange()
    XCTAssertEqual(center.addCount, added)
  }

  func testTheSettingsObserverPicksUpAutoStart() {
    timer = makeNotifyingTimer(autoStart: false)
    timer.startTimer()
    defaults.set(true, forKey: SettingsKey.autoStartBreaks)
    XCTAssertTrue(
      waitUntil {
        self.center.sessionPending?.content.categoryIdentifier
          == SessionNotification.autoStartedCategoryIdentifier
      })
  }

  // MARK: - Relaunch

  func testRelaunchWithTimeLeftSchedulesTheCopyAgain() {
    timer = makeNotifyingTimer(focus: 300)
    timer.startTimer()
    timer = nil
    center.pending = [:]
    advanceClock(by: 100)
    timer = makeNotifyingTimer(focus: 300)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(center.pending.count, 1)
    XCTAssertEqual(center.pendingInterval, 200 + delay)
    XCTAssertTrue(center.shown.isEmpty)
  }

  func testRelaunchAfterTheEndSchedulesNothing() {
    timer = makeNotifyingTimer(autoStart: false, focus: 300)
    timer.startTimer()
    timer = nil
    advanceClock(by: 300 + PomodoroTimer.overdueGracePeriod + 60)
    timer = makeNotifyingTimer(autoStart: false, focus: 300)
    XCTAssertEqual(timer.state, .idle)
    XCTAssertNil(center.sessionPending)
    XCTAssertTrue(center.shown.isEmpty, "no late notification on top of the copy")
  }

  func testRelaunchPausedCancelsALeftoverCopy() {
    timer.startTimer()
    timer.pauseTimer()
    timer = nil
    center.pending[SessionNotification.sessionCompleteIdentifier] =
      UNNotificationRequest(
        identifier: SessionNotification.sessionCompleteIdentifier,
        content: UNNotificationContent(),
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
    timer = makeNotifyingTimer()
    XCTAssertEqual(timer.state, .paused)
    XCTAssertNil(center.sessionPending)
  }
}
