//  Created by homielab.com

import AVFoundation
import AppKit
import Combine
import SwiftUI
import UserNotifications

class PomodoroTimer: ObservableObject {
  // MARK: - Published Properties for UI
  @Published var timeRemaining: Int = 0
  @Published var state: PomodoroState = .idle
  @Published var currentSessionType: SessionType = .focus
  @Published var focusSessionsCompleted: Int = 0
  @Published var progress: Double = 1.0
  @Published var isWaitingToContinue: Bool = false
  /// The break was put off with `postponeBreak(minutes:)`: the countdown runs
  /// until the break comes back, and the break overlay stays hidden.
  @Published private(set) var isBreakPostponed: Bool = false

  // MARK: - Settings
  // Settings are read live from the injected defaults on every use, so changes
  // made in the settings UI apply to the running timer just like @AppStorage did.
  let defaults: UserDefaults
  /// Source of wall-clock time; tests inject a fixed clock.
  private let now: () -> Date
  /// Seconds on a clock that keeps running during sleep and ignores changes to
  /// the system time; used to keep a session's length when the clock is set.
  private let uptime: () -> TimeInterval
  /// Log of completed sessions behind the "Today" statistics.
  let history: SessionHistory
  /// Hands a "session complete" notification to the system; tests capture it.
  let postNotification: (UNNotificationRequest) -> Void
  /// Plays a sound by name at a volume (`AlarmSound.play`); tests capture it.
  private let playSound: (String, Float) -> Void

  /// How long after its end a session may still sound the alarm and notify.
  /// Later than this (waking from a long sleep) it ends silently.
  static let overdueGracePeriod: TimeInterval = 5 * 60

  // MARK: - Private Properties
  var cancellables = Set<AnyCancellable>()
  private var timer: AnyCancellable?
  private var totalDuration: Int = 0
  /// When the latest tick fired, per `now`; lets tests verify the injected clock.
  private(set) var lastTickAt: Date?
  /// Wall-clock moment the running session ends. The remaining time is always
  /// derived from it, so sleep, App Nap or late timer fires cannot stretch a
  /// session. `nil` unless the timer is active.
  private(set) var endDate: Date? {
    didSet { endUptime = endDate.map { uptime() + $0.timeIntervalSince(now()) } }
  }
  /// `endDate` on the `uptime` clock.
  private var endUptime: TimeInterval?

  /// How the running session refreshes `timeRemaining`. With `.atEnd` the
  /// countdown is only brought up to date when the mode changes back, on
  /// pause, wake or a clock change, and when the session ends.
  var tickMode: TickMode = .everySecond {
    didSet {
      guard tickMode != oldValue, state == .active else { return }
      handleTick()
      if state == .active {
        startTicking()
      }
    }
  }

  init(
    defaults: UserDefaults = .standard,
    now: @escaping () -> Date = { Date() },
    workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    distributedNotificationCenter: NotificationCenter = DistributedNotificationCenter.default(),
    history: SessionHistory = SessionHistory(fileURL: nil),
    notificationCenter: NotificationCenter = .default,
    uptime: @escaping () -> TimeInterval = PomodoroTimer.continuousUptime,
    postNotification: @escaping (UNNotificationRequest) -> Void = {
      UNUserNotificationCenter.current().add($0)
    },
    playSound: @escaping (String, Float) -> Void = { AlarmSound.play($0, volume: $1) }
  ) {
    self.defaults = defaults
    self.postNotification = postNotification
    self.playSound = playSound
    self.now = now
    self.uptime = uptime
    self.history = history
    resetForCurrentSession()
    if let snapshot = TimerSnapshot.load(from: defaults) {
      restore(snapshot)
    }
    saveSnapshot()

    workspaceNotificationCenter.publisher(for: NSWorkspace.willSleepNotification)
      .sink { [weak self] _ in self?.handleWillSleep() }
      .store(in: &cancellables)
    workspaceNotificationCenter.publisher(for: NSWorkspace.didWakeNotification)
      .sink { [weak self] _ in self?.handleDidWake() }
      .store(in: &cancellables)
    // With "Pause when the Mac sleeps or the screen locks" on, the display
    // going to sleep or the screen locking pauses a running session too.
    workspaceNotificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)
      .sink { [weak self] _ in self?.handleScreenInactive() }
      .store(in: &cancellables)
    distributedNotificationCenter
      .publisher(for: Notification.Name(PomodoroTimer.screenLockedNotificationName))
      .sink { [weak self] _ in self?.handleScreenInactive() }
      .store(in: &cancellables)
    // Settings → Durations writes to these defaults; an idle timer shows the
    // new length right away instead of on the next Start.
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
      .sink { [weak self] _ in
        if Thread.isMainThread {
          self?.handleDefaultsChange()
        } else {
          DispatchQueue.main.async { self?.handleDefaultsChange() }
        }
      }
      .store(in: &cancellables)
    notificationCenter.publisher(for: .NSSystemClockDidChange)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.handleSystemClockChange() }
      .store(in: &cancellables)

    #if DEBUG
      print("--- TimeMate running in DEBUG mode (timers are in seconds) ---")
    #endif
  }

  func startTimer() {
    defer { saveSnapshot() }
    if state != .paused {
      resetForCurrentSession()
    }
    state = .active
    endDate = now().addingTimeInterval(TimeInterval(timeRemaining))
    startTicking()
  }

  /// Schedules `handleTick` for the current `tickMode`: every second, or
  /// once at `endDate` when nothing shows the countdown.
  private func startTicking() {
    timer?.cancel()
    switch tickMode {
    case .everySecond:
      timer = Timer.publish(every: 1, tolerance: TickMode.tolerance, on: .main, in: .common)
        .autoconnect()
        .sink { [weak self] _ in
          self?.handleTick()
        }
    case .atEnd:
      guard let endDate else { return }
      let delay = max(0, endDate.timeIntervalSince(now()))
      let endTimer = Timer(fire: Date().addingTimeInterval(delay), interval: 0, repeats: false) {
        [weak self] _ in
        guard let self else { return }
        self.handleTick()
        // Still running: a postponed break came back, or the clock moved.
        if self.state == .active {
          self.startTicking()
        }
      }
      endTimer.tolerance = TickMode.tolerance
      RunLoop.main.add(endTimer, forMode: .common)
      timer = AnyCancellable { endTimer.invalidate() }
    }
  }

  /// Seconds left in the running session, up to date even when ticks are
  /// sparse (`TickMode.atEnd`).
  var secondsRemaining: Int {
    guard state == .active, let endDate else { return timeRemaining }
    return max(0, Int(endDate.timeIntervalSince(now()).rounded()))
  }

  /// A clock on `uptime` that ignores system time changes and counts sleep.
  static func continuousUptime() -> TimeInterval {
    TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
  }

  /// One tick of the state machine: recompute the remaining time from `endDate`
  /// and, once it is reached, finish the session. Internal so tests can drive
  /// ticks without waiting on real timers.
  func handleTick() {
    let tickTime = now()
    lastTickAt = tickTime
    guard state == .active, let endDate else { return }

    if isBreakPostponed, endDate <= tickTime {
      // The postponed break comes back at its full length.
      resetForCurrentSession()
      self.endDate = tickTime.addingTimeInterval(TimeInterval(timeRemaining))
      saveSnapshot()
      return
    }

    let remaining = max(0, Int(endDate.timeIntervalSince(tickTime).rounded()))
    if remaining > 0 {
      timeRemaining = remaining
      progress = Double(timeRemaining) / Double(max(1, totalDuration))
    } else {
      timeRemaining = 0
      progress = 0
      self.endDate = nil
      timer?.cancel()
      // Only sessions that run to the end count; skipping never reaches here.
      let pomodorosBefore = history.todayTotals().pomodoros
      history.recordCompletedSession(
        currentSessionType, duration: TimeInterval(totalDuration), end: endDate,
        label: label(for: currentSessionType))
      // A session that ended long ago (the Mac slept through it) finishes
      // silently, like one restored after quitting the app.
      if tickTime.timeIntervalSince(endDate) <= Self.overdueGracePeriod {
        playSound(
          AlarmSound.sound(afterCompleting: currentSessionType, in: defaults), Float(alarmVolume))
        sendNotification()
        sendDailyGoalNotificationIfReached(pomodorosBefore: pomodorosBefore)
      }

      switch SessionSequence.completion(
        of: currentSessionType, keepBreakScreenOpen: keepBreakScreenOpen)
      {
      case .waitOnBreakScreen:
        isWaitingToContinue = true
        state = .idle
      case .advance:
        advanceToNextSession()
      }
      saveSnapshot()
    }
  }

  /// The Mac is about to sleep: stop the ticking loop. `endDate` keeps counting
  /// in wall-clock time while the Mac sleeps.
  func handleWillSleep() {
    guard state == .active else { return }
    if defaults.bool(forKey: SettingsKey.pauseOnSleep) {
      pauseTimer()
      return
    }
    handleTick()
    timer?.cancel()
  }

  /// The Mac woke up: catch up with the wall clock right away. A session whose
  /// end passed during sleep finishes once, then ticking resumes if active.
  func handleDidWake() {
    guard state == .active else { return }
    handleTick()
    if state == .active {
      startTicking()
    }
  }

  /// The system time was changed (by hand, a time zone or a network sync):
  /// move `endDate` so the session keeps the length it had left instead of
  /// being cut short or stretched by the jump.
  func handleSystemClockChange() {
    guard state == .active, let endUptime else { return }
    endDate = now().addingTimeInterval(endUptime - uptime())
    handleTick()
    if state == .active {
      startTicking()
    }
    saveSnapshot()
  }

  /// The defaults changed: an idle timer that isn't waiting on the break
  /// screen picks up a new length for its session. Only the display changes;
  /// nothing is recorded and a running or paused session keeps its length.
  func handleDefaultsChange() {
    guard state == .idle, !isWaitingToContinue,
      durationFor(session: currentSessionType) != totalDuration
    else { return }
    resetForCurrentSession()
  }

  func pauseTimer() {
    guard state == .active else { return }
    // Freeze the exact remaining time; if the session already ended, finish it
    // instead of pausing whatever comes next.
    let runningEndDate = endDate
    handleTick()
    guard state == .active, endDate == runningEndDate else { return }
    state = .paused
    endDate = nil
    timer?.cancel()
    saveSnapshot()
  }

  func stopTimer() {
    defer { saveSnapshot() }
    isWaitingToContinue = false
    state = .idle
    endDate = nil
    timer?.cancel()
    resetForCurrentSession()
  }

  func skipSession() {
    defer { saveSnapshot() }
    isWaitingToContinue = false
    endDate = nil
    timer?.cancel()
    advanceToNextSession()
  }

  func restartCycle() {
    defer { saveSnapshot() }
    isWaitingToContinue = false
    state = .idle
    focusSessionsCompleted = 0
    currentSessionType = .focus
    endDate = nil
    timer?.cancel()
    resetForCurrentSession()
  }

  func continueWork() {
    defer { saveSnapshot() }
    isWaitingToContinue = false
    advanceToNextSession()
    if state != .active {
      startTimer()
    }
  }

  /// Moves on to the session after the current one and starts it when
  /// `start` (by default the auto-start setting for that kind of session) is on.
  private func advanceToNextSession(start: Bool? = nil) {
    let next = SessionSequence.next(
      after: .init(
        sessionType: currentSessionType, focusSessionsCompleted: focusSessionsCompleted),
      interval: longBreakInterval)
    currentSessionType = next.sessionType
    focusSessionsCompleted = next.focusSessionsCompleted
    resetForCurrentSession()
    if start ?? autoStart.shouldStart(next: next.sessionType) {
      startTimer()
    } else {
      state = .idle
    }
  }

  /// Whether the current session is a break.
  var isBreak: Bool {
    SessionSequence.isBreak(currentSessionType)
  }

  /// Adds `minutes` to the running break ("+5 min" on the break screen). A
  /// break that already ended and waits on the break screen starts again for
  /// `minutes`. Does nothing during focus or a postponed break.
  func extend(by minutes: Int) {
    guard
      let adjustment = SessionSequence.extend(
        countdown, by: Self.seconds(forMinutes: minutes), now: now())
    else { return }
    let wasWaiting = isWaitingToContinue
    isWaitingToContinue = false
    apply(adjustment)
    if wasWaiting { startTicking() }
    saveSnapshot()
  }

  /// Puts off the running break by `minutes`: the break screen goes away and
  /// the break starts again, at its full length, once they have passed.
  func postponeBreak(minutes: Int) {
    guard
      let adjustment = SessionSequence.postpone(
        countdown, delay: Self.seconds(forMinutes: minutes), now: now())
    else { return }
    isBreakPostponed = true
    apply(adjustment)
    startTicking()
    saveSnapshot()
  }

  private var countdown: SessionSequence.Countdown {
    SessionSequence.Countdown(
      sessionType: currentSessionType, state: state, totalDuration: totalDuration,
      timeRemaining: timeRemaining, endDate: endDate, isBreakPostponed: isBreakPostponed,
      isWaitingToContinue: isWaitingToContinue)
  }

  private func apply(_ adjustment: SessionSequence.Adjustment) {
    state = adjustment.state
    totalDuration = adjustment.totalDuration
    timeRemaining = adjustment.timeRemaining
    endDate = adjustment.endDate
    progress = adjustment.progress
  }

  // MARK: - Saved state

  /// Saves what is needed to pick the session up again after a relaunch.
  private func saveSnapshot() {
    TimerSnapshot(
      state: state, sessionType: currentSessionType, endDate: endDate,
      remaining: timeRemaining, totalDuration: totalDuration,
      focusSessionsCompleted: focusSessionsCompleted, isBreakPostponed: isBreakPostponed,
      isWaitingToContinue: isWaitingToContinue
    ).save(to: defaults)
  }

  /// Picks up the session saved before the app quit. A running session keeps
  /// counting from its end date and a paused one stays paused. A session that
  /// ended while the app was closed is recorded in the history on the day it
  /// ended and the next session follows, without the alarm or a late
  /// notification. A waiting break screen or a postponed break that is due
  /// is not shown at launch: the timer waits on the next session instead.
  private func restore(_ snapshot: TimerSnapshot) {
    currentSessionType = snapshot.sessionType
    focusSessionsCompleted = snapshot.focusSessionsCompleted
    resetForCurrentSession()

    switch TimerRestorePlan.make(
      from: snapshot, now: now(), autoStart: autoStart,
      keepBreakScreenOpen: keepBreakScreenOpen)
    {
    case .idle:
      break
    case .advanceFromWaitingBreak:
      advanceToNextSession(start: false)
    case .paused(let remaining, let total, let postponed):
      isBreakPostponed = postponed
      totalDuration = total
      timeRemaining = remaining
      progress = Double(timeRemaining) / Double(max(1, totalDuration))
      state = .paused
    case .resume(let end, let remaining, let total, let postponed):
      isBreakPostponed = postponed
      totalDuration = total
      endDate = end
      timeRemaining = remaining
      progress = Double(timeRemaining) / Double(max(1, totalDuration))
      state = .active
      startTicking()
    case .postponedBreakDue:
      state = .idle
    case .expired(let end, let duration, let startNext):
      history.recordCompletedSession(
        currentSessionType, duration: TimeInterval(duration), end: end,
        label: label(for: currentSessionType))
      advanceToNextSession(start: startNext)
    }
  }

  private func resetForCurrentSession() {
    isBreakPostponed = false
    self.totalDuration = durationFor(session: currentSessionType)
    self.timeRemaining = totalDuration
    self.progress = 1.0
  }

}
