//  Created by homielab.com

import AppKit
import Combine
import XCTest

@testable import TimeMate

/// Shared fixture for the `PomodoroTimer` tests: a fake wall clock and uptime clock,
/// isolated defaults and in-memory history, plus the helpers the test files share.
class TimerTestCase: XCTestCase {
  static let suiteName = "TimeMateTests"

  var defaults: UserDefaults!
  var currentTime: Date!
  var workspaceCenter: NotificationCenter!
  var clockCenter: NotificationCenter!
  var distributedCenter: NotificationCenter!
  /// The fake `uptime` clock: moves with real time, not with clock changes.
  var currentUptime: TimeInterval = 0
  var history: SessionHistory!
  var timer: PomodoroTimer!
  /// How often the timer took the "session complete" notification away.
  var notificationRemovals = 0
  /// Resumes after unlock the timer scheduled, with their delays; run them
  /// with `runScheduledResumes()`.
  var scheduledResumes: [(delay: TimeInterval, block: () -> Void)] = []
  /// Seconds since the last keyboard or mouse input, as the timer reads them.
  var idleTime: TimeInterval = 0
  /// Fake "another app keeps the display awake" (a meeting, a video).
  var displayKeptAwake = false
  /// Pending idle checks of "Auto-pause when I'm away" (at most one is live);
  /// run the next with `runIdleCheck()`.
  var idleChecks: [(id: Int, delay: TimeInterval, block: () -> Void)] = []
  private var nextIdleCheckID = 0

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
    currentTime = Date(timeIntervalSince1970: 1_000_000)
    workspaceCenter = NotificationCenter()
    clockCenter = NotificationCenter()
    distributedCenter = NotificationCenter()
    currentUptime = 50_000
    notificationRemovals = 0
    scheduledResumes = []
    idleTime = 0
    displayKeptAwake = false
    idleChecks = []
    // A fixed calendar: the fake clock starts at 13:46 UTC, so calendar days
    // (and the stale-cycle rule) don't depend on the Mac's time zone.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    history = SessionHistory(
      fileURL: nil,
      now: { [weak self] in self?.currentTime ?? Date(timeIntervalSince1970: 0) },
      calendar: calendar)
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
  func makeTimer(
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
      uptime: { [weak self] in self?.currentUptime ?? 0 },
      removeSessionNotifications: { [weak self] in self?.notificationRemovals += 1 },
      removePendingSessionNotification: {},
      isFullscreenProbe: { false },
      scheduleResume: { [weak self] in self?.scheduledResumes.append((delay: $0, block: $1)) },
      idleSeconds: { [weak self] in self?.idleTime ?? 0 },
      isDisplayKeptAwake: { [weak self] in self?.displayKeptAwake ?? false },
      scheduleIdleCheck: { [weak self] delay, block in
        guard let self else { return AnyCancellable {} }
        let id = self.nextIdleCheckID
        self.nextIdleCheckID += 1
        self.idleChecks.append((id: id, delay: delay, block: block))
        return AnyCancellable { [weak self] in self?.idleChecks.removeAll { $0.id == id } }
      })
  }

  /// Lets the delay of the pending idle check pass on the fake clock (the
  /// idle time grows with it while `away`), then runs it.
  func runIdleCheck(away: Bool = true) {
    guard let check = idleChecks.first else { return XCTFail("No idle check scheduled") }
    idleChecks.removeFirst()
    advanceClock(by: check.delay)
    if away {
      idleTime += check.delay
    }
    check.block()
  }

  /// Lets each scheduled resume's delay pass on the fake clock, then runs it.
  func runScheduledResumes() {
    let pending = scheduledResumes
    scheduledResumes = []
    for resume in pending {
      advanceClock(by: resume.delay)
      resume.block()
    }
  }

  /// Advances the fake clock one second per tick, like the real 1 s timer.
  func runTicks(_ timer: PomodoroTimer, _ count: Int) {
    for _ in 0..<count {
      advanceClock(by: 1)
      timer.handleTick()
    }
  }

  /// Lets `seconds` of real time pass.
  func advanceClock(by seconds: TimeInterval) {
    currentTime = currentTime.addingTimeInterval(seconds)
    currentUptime += seconds
  }

  /// Sets the system time forward (or back) by `seconds`; no time passes.
  func setSystemClock(by seconds: TimeInterval) {
    currentTime = currentTime.addingTimeInterval(seconds)
  }

  func finishSession(_ timer: PomodoroTimer) {
    runTicks(timer, timer.timeRemaining)
  }

  /// A timer whose alarm and notification are recorded: (sounds, notifications).
  func makeAlertTimer() -> (PomodoroTimer, () -> Int, () -> Int) {
    var sounds = 0
    var posts = 0
    defaults.set(3, forKey: SettingsKey.focusDuration)
    defaults.set(2, forKey: SettingsKey.shortBreakDuration)
    defaults.set(true, forKey: SettingsKey.notificationsEnabled)
    defaults.set(true, forKey: SettingsKey.autoStartNextSession)
    let alertTimer = PomodoroTimer(
      defaults: defaults,
      now: { [weak self] in self?.currentTime ?? Date(timeIntervalSince1970: 0) },
      workspaceNotificationCenter: workspaceCenter,
      distributedNotificationCenter: distributedCenter,
      history: history,
      notificationCenter: clockCenter,
      uptime: { [weak self] in self?.currentUptime ?? 0 },
      // Counts only notifications shown now, not the copy scheduled for a session's end.
      postNotification: { if $0.trigger == nil { posts += 1 } },
      removeSessionNotifications: { [weak self] in self?.notificationRemovals += 1 },
      removePendingSessionNotification: {},
      playSound: { _, _ in sounds += 1 },
      isFullscreenProbe: { false })
    return (alertTimer, { sounds }, { posts })
  }

  /// Drops the running timer and builds a new one from the same defaults and
  /// clock, as when the app quits and opens again.
  func relaunch(
    after seconds: TimeInterval, focus: Int = 300, autoStart: Bool = true,
    keepBreakOpen: Bool = false
  ) -> PomodoroTimer {
    timer = nil
    advanceClock(by: seconds)
    return makeTimer(focus: focus, autoStart: autoStart, keepBreakOpen: keepBreakOpen)
  }
}

extension XCTestCase {
  /// Runs the main run loop in 10 ms steps until `condition` holds or `timeout` passes.
  /// Returns whether the condition held; no fixed wait, so a quick answer returns at once.
  @discardableResult
  func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
      if Date() >= deadline { return false }
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return true
  }

  /// Returns once everything already queued on the main queue has run.
  func drainMainQueue() {
    var drained = false
    DispatchQueue.main.async { drained = true }
    waitUntil { drained }
  }
}
