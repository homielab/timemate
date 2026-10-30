//  Created by homielab.com

import AVFoundation
import AppKit
import Combine
import SwiftUI
import UserNotifications
import os

class PomodoroTimer: ObservableObject {
  // MARK: - Published Properties for UI
  @Published var timeRemaining: Int = 0
  @Published var state: PomodoroState = .idle {
    didSet {
      refreshCanExtend()
      if state != oldValue { updateIdleWatch() }
    }
  }
  @Published var currentSessionType: SessionType = .focus {
    didSet {
      if currentSessionType != oldValue { updateIdleWatch() }
    }
  }
  @Published var focusSessionsCompleted: Int = 0 {
    didSet { if focusSessionsCompleted == 0 { cycleStartedAt = now() } }
  }
  /// When the count of focus sessions last went back to 0 (a long break, a
  /// restarted cycle); `nil` when unknown. Decides whether an undone session
  /// was counted in the current cycle (`SessionCycle.countAfterUndo`).
  private(set) var cycleStartedAt: Date?
  @Published var progress: Double = 1.0
  @Published var isWaitingToContinue: Bool = false {
    didSet { refreshCanExtend() }
  }
  /// The break was put off with `postponeBreak(minutes:)`: the countdown runs
  /// until the break comes back, and the break overlay stays hidden.
  @Published private(set) var isBreakPostponed: Bool = false {
    didSet { refreshCanExtend() }
  }
  /// Whether "+5 min" / "Add Time" can still lengthen the session: false once it
  /// reaches the 180-minute limit or while a break is postponed, so the buttons
  /// show as disabled. A break waiting on the break screen can be extended.
  @Published private(set) var canExtend: Bool = true

  // MARK: - Settings
  // Settings are read live from the injected defaults on every use, so changes
  // made in the settings UI apply to the running timer just like @AppStorage did.
  let defaults: UserDefaults
  /// Source of wall-clock time; tests inject a fixed clock.
  let now: () -> Date
  /// Seconds on a clock that keeps running during sleep and ignores changes to
  /// the system time; used to keep a session's length when the clock is set.
  private let uptime: () -> TimeInterval
  /// Log of completed sessions behind the "Today" statistics.
  let history: SessionHistory
  /// Hands a "session complete" notification to the system; tests capture it.
  let postNotification: (UNNotificationRequest) -> Void
  /// Takes the "session complete" notification out of Notification Center once
  /// the user moves on, so its buttons can't act on a later session; tests count calls.
  let removeSessionNotifications: () -> Void
  /// Cancels the scheduled copy of the "session complete" notification; tests track it.
  let removePendingSessionNotification: () -> Void
  /// Plays a sound by name at a volume (`AlarmSound.play`); tests capture it.
  private let playSound: (String, Float) -> Void
  /// Whether the app in front covers a screen (`OverlayPolicy.isFrontmostAppFullscreen`).
  let isFullscreenProbe: () -> Bool

  /// How long after its end a session may still sound the alarm, notify and
  /// start the next session. Later than this (waking from a long sleep or
  /// opening the app again) it ends silently and the next session waits.
  static let overdueGracePeriod: TimeInterval = 5 * 60

  /// The session end and the text of the scheduled copy of the "session
  /// complete" notification (`syncFallbackNotification`); `nil` when none was
  /// scheduled.
  var scheduledFallback: ScheduledFallback?
  /// A scheduled copy may still be pending: one from the last run of the app,
  /// or one this run scheduled and has not cancelled or replaced.
  var fallbackMayBePending = true

  // MARK: - Private Properties
  var cancellables = Set<AnyCancellable>()
  private var defaultsObserver: DefaultsObserver?
  private var timer: AnyCancellable?
  private var totalDuration: Int = 0 {
    didSet { refreshCanExtend() }
  }
  /// The label of the session as it began ("" = none), so typing the next task
  /// before the bell does not relabel the one just done. `nil` = not captured
  /// (a snapshot from an older version): the label field is read live.
  private(set) var startedLabel: String?
  /// Length in seconds of the focus session `startFocus(minutes:)` is about to
  /// begin, used instead of the Focus setting for that session only.
  private var oneOffFocusSeconds: Int?
  /// When a session last began or ended; an idle timer whose cycle is older
  /// than `SessionCycle.isStale` allows starts the cycle over.
  private(set) var lastActivity: Date?
  /// When the paused session was paused; `nil` unless paused (or unknown, from
  /// an older snapshot). Resuming after a stale pause starts the cycle over.
  private(set) var pausedAt: Date?
  /// The paused session was paused by sleep, a locked screen or the user being
  /// away, not by the user; with `resumeOnReturn` on it continues when the user is back.
  var pausedBySleep = false {
    didSet {
      if pausedBySleep != oldValue { updateIdleWatch() }
    }
  }
  /// Whether the screen is locked, per the system's lock and unlock notifications.
  var isScreenLocked = false
  /// Runs a block after a delay; the resume after unlock waits `resumeDelay`.
  /// Tests collect the blocks and run them.
  let scheduleResume: (TimeInterval, @escaping () -> Void) -> Void
  /// Seconds since the last keyboard, mouse or trackpad input
  /// (`systemIdleSeconds`); tests inject a fake.
  let idleSeconds: () -> TimeInterval
  /// Whether another app keeps the display awake (`DisplayAwakeProbe`); a
  /// session then doesn't pause as away, and with "Wait during calls and video"
  /// the break screen doesn't appear. Tests inject a fake.
  let isDisplayKeptAwake: () -> Bool
  /// Runs a block once after a delay (`scheduleOnMainRunLoop`); the idle checks
  /// of "Auto-pause when I'm away" use it. Tests collect the blocks and run them.
  let scheduleIdleCheck: (TimeInterval, @escaping () -> Void) -> AnyCancellable
  /// The next idle check (`updateIdleWatch`); `nil` when none is due.
  var idleWatch: AnyCancellable?
  /// When the current session began, before any pause; `nil` when none runs or
  /// it came from a snapshot saved before this was kept (the history then
  /// takes the end minus the duration).
  private(set) var startedAt: Date?
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
  /// countdown is only brought up to date (`.everyMinute`: once a minute) when the mode changes back, on
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
    postNotification: @escaping (UNNotificationRequest) -> Void = { SessionNotification.post($0) },
    removeSessionNotifications: @escaping () -> Void = SessionNotification.removeDelivered,
    removePendingSessionNotification: @escaping () -> Void = SessionNotification.removePending,
    playSound: @escaping (String, Float) -> Void = { AlarmSound.play($0, volume: $1) },
    isFullscreenProbe: @escaping () -> Bool = OverlayPolicy.isFrontmostAppFullscreen,
    scheduleResume: @escaping (TimeInterval, @escaping () -> Void) -> Void = {
      DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1)
    },
    idleSeconds: @escaping () -> TimeInterval = PomodoroTimer.systemIdleSeconds,
    isDisplayKeptAwake: @escaping () -> Bool = DisplayAwakeProbe.isKeptAwakeByOtherApp,
    scheduleIdleCheck: @escaping (TimeInterval, @escaping () -> Void) -> AnyCancellable =
      PomodoroTimer.scheduleOnMainRunLoop
  ) {
    self.isFullscreenProbe = isFullscreenProbe
    self.scheduleResume = scheduleResume
    self.idleSeconds = idleSeconds
    self.isDisplayKeptAwake = isDisplayKeptAwake
    self.scheduleIdleCheck = scheduleIdleCheck
    self.defaults = defaults
    self.postNotification = postNotification
    self.removeSessionNotifications = removeSessionNotifications
    self.removePendingSessionNotification = removePendingSessionNotification
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
    // The user is back: with "Resume when I'm back" on, a session paused by
    // sleep or the lock continues (`handleUserReturned`).
    workspaceNotificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
      .sink { [weak self] _ in self?.handleUserReturned() }
      .store(in: &cancellables)
    distributedNotificationCenter
      .publisher(for: Notification.Name(PomodoroTimer.screenLockedNotificationName))
      .sink { [weak self] _ in
        self?.isScreenLocked = true
        self?.handleScreenInactive()
      }
      .store(in: &cancellables)
    distributedNotificationCenter
      .publisher(for: Notification.Name(PomodoroTimer.screenUnlockedNotificationName))
      .sink { [weak self] _ in
        self?.isScreenLocked = false
        self?.handleUserReturned()
      }
      .store(in: &cancellables)
    // Settings → Durations writes to these defaults; an idle timer shows the
    // new length right away instead of on the next Start. The others change
    // what the scheduled "session complete" notification says.
    defaultsObserver = DefaultsObserver(
      defaults: defaults,
      keys: [
        SettingsKey.focusDuration, SettingsKey.shortBreakDuration, SettingsKey.longBreakDuration,
        SettingsKey.notificationsEnabled, SettingsKey.longBreakInterval,
        SettingsKey.autoStartNextSession, SettingsKey.autoStartBreaks, SettingsKey.autoStartFocus,
        SettingsKey.keepBreakScreenOpen, SettingsKey.overlayEnabled,
        SettingsKey.overlaySkipFullscreen, SettingsKey.overlayWaitDuringCalls,
        SettingsKey.breakThroughFocus,
        SettingsKey.idlePauseMinutes, SettingsKey.resumeOnReturn, SettingsKey.sessionLabel,
      ]
    ) { [weak self] in self?.handleDefaultsChange() }
    notificationCenter.publisher(for: .NSSystemClockDidChange)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.handleSystemClockChange() }
      .store(in: &cancellables)
    // Midnight passed with the timer idle: show the fresh cycle Start will run.
    notificationCenter.publisher(for: .NSCalendarDayChanged)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.refreshStaleCycle() }
      .store(in: &cancellables)
    // Quit, an update, logging out or shutting down: delivered synchronously,
    // before the app exits, so the paused snapshot is saved.
    notificationCenter.publisher(for: NSApplication.willTerminateNotification)
      .sink { [weak self] _ in self?.handleWillTerminate() }
      .store(in: &cancellables)

    #if DEBUG
      Logger.app.debug("TimeMate running in DEBUG mode (timers are in seconds)")
    #endif
  }

  /// Takes the "session complete" notification away, shown or scheduled.
  private func clearSessionNotifications() {
    removeSessionNotifications()
    scheduledFallback = nil
    fallbackMayBePending = false
  }

  /// Starts or resumes the current session for the user.
  func startTimer() {
    clearSessionNotifications()
    if state == .idle {
      restartCycleIfStale()
    } else if state == .paused,
      SessionCycle.pauseRestartsCycle(pausedAt: pausedAt, now: now(), calendar: history.calendar)
    {
      // Paused last night, resumed this morning: the session keeps the time
      // it has left, but the pomodoros before it no longer count.
      focusSessionsCompleted = 0
    }
    beginSession()
  }

  /// Starts or resumes the current session; also the auto-start after a
  /// session ends, which must keep the notification it has just posted.
  private func beginSession() {
    defer { saveSnapshot() }
    if state != .paused {
      resetForCurrentSession()
      if currentSessionType == .focus, let seconds = oneOffFocusSeconds {
        totalDuration = seconds
        timeRemaining = seconds
      }
      startedLabel = sessionLabel ?? ""
      startedAt = now()
    }
    state = .active
    pausedAt = nil
    pausedBySleep = false
    lastActivity = now()
    endDate = now().addingTimeInterval(TimeInterval(timeRemaining))
    startTicking()
  }

  /// Restarts a stale idle cycle now (`restartCycleIfStale`) and saves it, so
  /// the popover and menu bar show what Start will run: called on wake, before
  /// the popover opens and when the day changes.
  func refreshStaleCycle() {
    let before = (currentSessionType, focusSessionsCompleted, isWaitingToContinue)
    restartCycleIfStale()
    guard before != (currentSessionType, focusSessionsCompleted, isWaitingToContinue) else {
      return
    }
    saveSnapshot()
  }

  /// Starts the cycle over on focus, with no sessions counted, when the timer
  /// is idle and the last session is over four hours old, or from another day
  /// and over an hour old (`SessionCycle.isStale`): three pomodoros last night
  /// do not make this morning's first one end in a long break. A running or paused
  /// session is never touched here (a stale pause resets in `startTimer`).
  private func restartCycleIfStale() {
    guard state == .idle,
      focusSessionsCompleted != 0 || currentSessionType != .focus || isWaitingToContinue,
      SessionCycle.isStale(lastActivity: lastActivity, now: now(), calendar: history.calendar)
    else { return }
    isWaitingToContinue = false
    focusSessionsCompleted = 0
    currentSessionType = .focus
    startedLabel = nil
    startedAt = nil
    resetForCurrentSession()
  }

  /// Schedules `handleTick` for the current `tickMode`: every second, at each
  /// change of the minutes shown, or once at `endDate` when nothing shows the countdown.
  private func startTicking() {
    timer?.cancel()
    guard !isRelaunching else { return }
    switch tickMode {
    case .everySecond:
      timer = Timer.publish(every: 1, tolerance: TickMode.tolerance, on: .main, in: .common)
        .autoconnect()
        .sink { [weak self] _ in
          self?.handleTick()
        }
    case .atEnd, .everyMinute:
      guard let endDate else { return }
      let untilEnd = max(0, endDate.timeIntervalSince(now()))
      let delay =
        tickMode == .everyMinute
        ? MenuBarTimeStyle.secondsUntilMinuteChange(remaining: untilEnd) : untilEnd
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
    guard state == .active, !isRelaunching, let endDate else { return }

    let isLongOverdue = tickTime.timeIntervalSince(endDate) > Self.overdueGracePeriod
    if isBreakPostponed, endDate <= tickTime {
      // The postponed break comes back at its full length; long after it came
      // due (the Mac slept) it waits for Start instead of covering the screen.
      resetForCurrentSession()
      startedAt = isLongOverdue ? nil : tickTime
      if isLongOverdue {
        self.endDate = nil
        timer?.cancel()
        state = .idle
        // Slept through the night: start the cycle over now, so what the
        // popover shows is what Start runs.
        restartCycleIfStale()
      } else {
        self.endDate = tickTime.addingTimeInterval(TimeInterval(timeRemaining))
      }
      saveSnapshot()
      return
    }
    if pauseIfAway(at: tickTime, endDate: endDate) { return }

    let remaining = max(0, Int(endDate.timeIntervalSince(tickTime).rounded()))
    if remaining > 0 {
      timeRemaining = remaining
      progress = Double(timeRemaining) / Double(max(1, totalDuration))
    } else {
      timeRemaining = 0
      progress = 0
      self.endDate = nil
      timer?.cancel()
      // The notification posted below stands in for the scheduled copy; when that
      // copy has already shown (the app was late), it is not posted again.
      let fallbackShown = fallbackNotificationShown(forEnd: endDate, at: tickTime)
      // The copy has its own identifier, so cancel it before it shows twice.
      if fallbackMayBePending && !fallbackShown {
        removePendingSessionNotification()
      }
      scheduledFallback = nil
      fallbackMayBePending = false
      lastActivity = endDate
      // Only sessions that run to the end count; skipping never reaches here.
      let pomodorosBefore = history.totals(on: endDate).pomodoros
      history.recordCompletedSession(
        currentSessionType, duration: TimeInterval(totalDuration), start: startedAt,
        end: endDate, label: sessionLabel(for: currentSessionType))
      // A session that ended long ago (the Mac slept through it) finishes
      // silently, like one restored after quitting the app, and the next
      // session waits for Start: no break screen for a break that is long gone.
      // Reaching the daily goal is still worth telling.
      if isLongOverdue {
        sendDailyGoalNotificationIfReached(pomodorosBefore: pomodorosBefore, endedAt: endDate)
        advanceToNextSession(start: false)
        restartCycleIfStale()
        saveSnapshot()
        return
      }
      let alarm = AlarmSound.sound(afterCompleting: currentSessionType, in: defaults)
      // A break screen held back by a full-screen app or a call holds back the
      // alarm too; it plays once the screen shows (`playPendingAlarm`).
      let breakScreenWaits = overlayEnabled && !breakScreenCanShow
      pendingAlarm = nil
      if !breakScreenWaits {
        playSound(alarm, Float(alarmVolume))
      }
      if !fallbackShown {
        sendNotification()
      }
      sendDailyGoalNotificationIfReached(pomodorosBefore: pomodorosBefore, endedAt: endDate)

      switch SessionSequence.completion(
        of: currentSessionType, keepBreakScreenOpen: keepBreakScreenOpen,
        breakScreenShown: breakScreenCanShow)
      {
      case .waitOnBreakScreen:
        isWaitingToContinue = true
        state = .idle
      case .advance:
        advanceToNextSession()
      }
      if breakScreenWaits {
        // Only a break gets a break screen; anything else rings now, as before.
        if state == .active && currentSessionType != .focus {
          pendingAlarm = alarm
        } else {
          playSound(alarm, Float(alarmVolume))
        }
      }
      saveSnapshot()
    }
  }

  /// "Auto-pause when I'm away": a running focus session whose user has been
  /// away for the chosen minutes pauses, with the time away given back, and
  /// counts as paused by the system (`pausedBySleep`), so "Resume when I'm back"
  /// continues it. Returns whether it paused.
  private func pauseIfAway(at tickTime: Date, endDate: Date) -> Bool {
    guard let threshold = IdlePausePolicy.threshold(minutes: idlePauseMinutes) else { return false }
    let idle = idleSeconds()
    guard
      IdlePausePolicy.shouldPause(
        state: state, isBreak: isBreak, idleSeconds: idle, threshold: threshold),
      !isDisplayKeptAwake()
    else { return false }
    let left = IdlePausePolicy.remainingAfterAway(
      secondsLeft: endDate.timeIntervalSince(tickTime), idleSeconds: idle,
      runningFor: lastActivity.map { tickTime.timeIntervalSince($0) } ?? .infinity,
      totalDuration: totalDuration)
    // Away only after the end: the session is over and counts.
    guard left > 0 else { return false }
    timeRemaining = left
    progress = Double(timeRemaining) / Double(max(1, totalDuration))
    enterPause(at: tickTime)
    pausedBySleep = true
    Logger.app.info("Paused the focus session: no input for \(Int(idle)) s")
    return true
  }

  /// TimeMate is quitting (Quit, an update, logging out or shutting down): a
  /// running session or postponed break pauses with the time it has left, as if
  /// the user paused it, so time the app was not running never counts and
  /// nothing is recorded. A crash or force quit gets no such call: the session
  /// then keeps counting in wall-clock time (`TimerRestorePlan`).
  /// An app restart (language change, Reset all settings) keeps the session
  /// running.
  func handleWillTerminate() {
    if isRelaunching { return }
    pauseTimer()
  }

  /// Set by `prepareForRelaunch()` before the new instance opens: the new instance
  /// picks the session up from the snapshot as if the app never closed, so this one
  /// no longer ticks, records or saves.
  private(set) var isRelaunching = false

  /// Saves the snapshot one last time and stops ticking, before `restartApp()`
  /// opens the new instance, so the two never both end the session.
  func prepareForRelaunch() {
    saveSnapshot()
    isRelaunching = true
    timer?.cancel()
    timer = nil
  }

  /// The new instance could not start: this one carries on.
  func cancelRelaunch() {
    guard isRelaunching else { return }
    isRelaunching = false
    if state == .active { startTicking() }
  }

  /// When the break screen of the running break first appeared; kept in the
  /// snapshot so a relaunch or a display change mid-break neither restarts the
  /// skip delay nor announces the break again. `nil` when no break screen is up.
  private(set) var breakScreenShownAt: Date?

  /// Records that the break screen appeared, unless it already did for this break.
  /// Returns when it first appeared.
  @discardableResult
  func markBreakScreenShown() -> Date {
    if let breakScreenShownAt { return breakScreenShownAt }
    let date = now()
    breakScreenShownAt = date
    saveSnapshot()
    return date
  }

  /// Whole seconds since this break's screen first appeared; `nil` when it hasn't.
  var secondsSinceBreakScreenShown: Int? {
    breakScreenShownAt.map { max(0, Int(now().timeIntervalSince($0).rounded(.down))) }
  }

  /// The break screen went away (the break ended, was postponed or paused).
  func clearBreakScreenShown() {
    guard breakScreenShownAt != nil else { return }
    breakScreenShownAt = nil
    saveSnapshot()
  }

  /// The Mac is about to sleep: stop the ticking loop. A focus session pauses
  /// when `pauseOnSleep` is on; anything else keeps `endDate` counting in
  /// wall-clock time while the Mac sleeps.
  func handleWillSleep() {
    guard state == .active else { return }
    if SleepPausePolicy.shouldPause(
      state: state, isBreak: isBreak,
      pauseOnSleep: defaults.bool(forKey: SettingsKey.pauseOnSleep))
    {
      pauseForSleep()
      return
    }
    handleTick()
    timer?.cancel()
  }

  /// The Mac woke up: catch up with the wall clock right away. A session whose
  /// end passed during sleep finishes once, then ticking resumes if active.
  /// A focus session paused by the sleep may resume (`handleUserReturned`).
  func handleDidWake() {
    handleUserReturned()
    guard state == .active else {
      refreshStaleCycle()
      return
    }
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
  /// Turning notifications on or off schedules or cancels the scheduled one;
  /// a setting that changes what it says (auto-start, the next session's
  /// length, the long break interval...) schedules it again with the new text.
  func handleDefaultsChange() {
    updateIdleWatch()
    syncFallbackNotification()
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
    enterPause(at: now())
  }

  /// Stops the countdown at `timeRemaining`; the user resumes it, unless the
  /// caller marks the pause as the system's (`pausedBySleep`).
  private func enterPause(at time: Date) {
    state = .paused
    pausedAt = time
    pausedBySleep = false
    endDate = nil
    timer?.cancel()
    saveSnapshot()
  }

  /// Resets the current session. On a finished break that waits on the break
  /// screen it moves on to a fresh focus session instead of replaying the break.
  /// `recording: true` (hotkey, Shortcuts, "Record and Reset") first records a
  /// focus session that ran past half, like Skip does.
  /// Returns the focus seconds recorded in the history (0 when none).
  @discardableResult
  func stopTimer(recording: Bool = false) -> TimeInterval {
    defer { saveSnapshot() }
    pendingAlarm = nil
    var recorded: TimeInterval = 0
    if recording, resetNeedsConfirmation {
      recorded = elapsedSeconds
      recordFocusSoFar(elapsed: recorded)
    }
    clearSessionNotifications()
    if isWaitingToContinue {
      isWaitingToContinue = false
      timer?.cancel()
      endDate = nil
      advanceToNextSession(start: false)
      return recorded
    }
    isWaitingToContinue = false
    state = .idle
    endDate = nil
    timer?.cancel()
    resetForCurrentSession()
    return recorded
  }

  /// Seconds left before the break screen allows Skip/Postpone; 0 when it is
  /// not showing or the delay is over. Set by the break screen controller.
  var breakScreenSkipLock: () -> Int = { 0 }

  /// The alarm of a session whose break screen is waiting (full-screen app or
  /// call); played once by `playPendingAlarm`, dropped on skip, reset or postpone.
  private(set) var pendingAlarm: String?

  /// Plays the alarm held back while the break screen waited. Called by the
  /// break screen controller when the screen shows.
  func playPendingAlarm() {
    guard let alarm = pendingAlarm else { return }
    pendingAlarm = nil
    playSound(alarm, Float(alarmVolume))
  }

  /// Seconds the break screen still blocks skipping and pausing from outside
  /// it (shortcuts, menu, notification, Shortcuts); 0 = allowed.
  var skipLockSeconds: Int {
    currentSessionType != .focus && !isWaitingToContinue ? max(0, breakScreenSkipLock()) : 0
  }

  /// "Skip available in N s", shown when a skip or pause is blocked.
  var skipLockText: String {
    String(format: NSLocalizedString("Skip available in %d s", comment: ""), skipLockSeconds)
  }

  func skipSession() {
    defer { saveSnapshot() }
    pendingAlarm = nil
    let elapsed = elapsedSeconds
    // Skipping a session that never started only picks the next one: it must
    // not start it (auto-start is for sessions that ran) or show the break screen.
    let wasIdle = state == .idle && !isWaitingToContinue
    let counts =
      state != .idle
      && SessionSequence.skipCounts(elapsed: elapsed, total: TimeInterval(totalDuration))
    // A focus session skipped past half counts in the cycle, so its real
    // focus time (pauses excluded) goes into History, Today and the goal too.
    if counts, currentSessionType == .focus {
      recordFocusSoFar(elapsed: elapsed)
    }
    clearSessionNotifications()
    isWaitingToContinue = false
    endDate = nil
    timer?.cancel()
    // Skipping picks the next session on purpose: Start must not undo it.
    lastActivity = now()
    // A focus session skipped before half of it ran is not counted.
    advanceToNextSession(start: wasIdle ? false : nil, counts: counts)
  }

  /// Focus time run so far in the current session, pauses excluded.
  private var elapsedSeconds: TimeInterval {
    TimeInterval(max(0, totalDuration - secondsRemaining))
  }

  /// Reset would throw away a focus session that ran past half: ask first
  /// (popover, menu) or record it (hotkey, Shortcuts).
  var resetNeedsConfirmation: Bool {
    !isWaitingToContinue
      && SessionSequence.resetNeedsConfirmation(
        sessionType: currentSessionType, state: state, elapsed: elapsedSeconds,
        total: TimeInterval(totalDuration))
  }

  /// Records the focus time run so far. A paused session ended at its pause,
  /// so one paused in the evening and skipped the next morning counts for the
  /// day and hour it ran, not for the moment it was ended.
  private func recordFocusSoFar(elapsed: TimeInterval) {
    let end = state == .paused ? (pausedAt ?? now()) : now()
    let pomodorosBefore = history.totals(on: end).pomodoros
    history.recordCompletedSession(
      .focus, duration: elapsed, start: startedAt, end: end,
      label: sessionLabel(for: .focus))
    sendDailyGoalNotificationIfReached(pomodorosBefore: pomodorosBefore, endedAt: end)
  }

  /// "Undo Last Session": removes `record` from the history if it is still the
  /// focus session recorded last and, when it counted in the current cycle,
  /// takes it off the cycle too, so the dots and the long break follow the
  /// history. Returns the removed record, `nil` if none.
  @discardableResult
  func undoLastFocusSession(matching record: SessionHistory.Record) -> SessionHistory.Record? {
    guard let removed = history.removeLastFocusSession(matching: record) else { return nil }
    // Back under the goal: the next pomodoro that reaches it notifies again.
    if history.todayTotals().pomodoros < dailyGoal {
      clearDailyGoalNotified()
    }
    let count = SessionCycle.countAfterUndo(
      sessionEnd: removed.end, cycleStartedAt: cycleStartedAt, completed: focusSessionsCompleted)
    if count != focusSessionsCompleted {
      focusSessionsCompleted = count
      saveSnapshot()
    }
    return removed
  }

  func restartCycle() {
    defer { saveSnapshot() }
    clearSessionNotifications()
    isWaitingToContinue = false
    state = .idle
    focusSessionsCompleted = 0
    currentSessionType = .focus
    endDate = nil
    timer?.cancel()
    resetForCurrentSession()
  }

  /// Starts or resumes the current session; past a finished break that waits
  /// on the break screen, continues with the next session. A running timer is
  /// left alone: this never pauses.
  func startOrContinue() {
    if isWaitingToContinue {
      continueWork()
    } else if state != .active {
      startTimer()
    }
  }

  /// Like `startOrContinue`, but asks for focus: an idle timer sitting on a
  /// break (the break did not start by itself) moves on to focus first, with
  /// the focus session before the break counted once, as it already was.
  /// With `minutes` (kept within `SessionDuration.minuteRange`), a focus
  /// session that begins now lasts that long instead of the Focus setting, which
  /// stays as it is; it counts in the cycle, history and goal like any other. A
  /// running or paused session keeps its length.
  func startFocus(minutes: Int? = nil) {
    if !isWaitingToContinue, state == .idle, isBreak {
      advanceToNextSession(start: false)
    }
    oneOffFocusSeconds = minutes.map {
      let range = SessionDuration.minuteRange
      return Self.seconds(forMinutes: min(max($0, range.lowerBound), range.upperBound))
    }
    defer { oneOffFocusSeconds = nil }
    startOrContinue()
  }

  /// Ends a break that waits on the break screen and starts the next session.
  /// A break left waiting overnight or for over four hours starts a fresh cycle
  /// (`SessionCycle.isStale`; a few minutes across midnight keep the cycle)
  /// on focus instead, like Start on a stale idle timer.
  func continueWork() {
    defer { saveSnapshot() }
    clearSessionNotifications()
    if isWaitingToContinue,
      SessionCycle.isStale(lastActivity: lastActivity, now: now(), calendar: history.calendar)
    {
      restartCycleIfStale()
      beginSession()
      return
    }
    isWaitingToContinue = false
    advanceToNextSession()
    if state != .active {
      beginSession()
    }
  }

  /// Moves on to the session after the current one and starts it when
  /// `start` (by default the auto-start setting for that kind of session) is on.
  private func advanceToNextSession(start: Bool? = nil, counts: Bool = true) {
    let next = SessionSequence.next(
      after: .init(
        sessionType: currentSessionType, focusSessionsCompleted: focusSessionsCompleted),
      interval: longBreakInterval, counts: counts)
    currentSessionType = next.sessionType
    focusSessionsCompleted = next.focusSessionsCompleted
    startedLabel = nil
    startedAt = nil
    resetForCurrentSession()
    if start ?? autoStart.shouldStart(next: next.sessionType) {
      beginSession()
    } else {
      state = .idle
    }
  }

  /// Whether the current session is a break.
  var isBreak: Bool {
    SessionSequence.isBreak(currentSessionType)
  }

  /// Adds `minutes` to the running or paused session ("+5 min" on the break screen
  /// or in the popover during focus; the history records the longer length). A
  /// break that already ended and waits on the break screen starts again for
  /// `minutes`. A session never grows past `SessionDuration.minuteRange`'s upper
  /// bound (180 minutes); only the part that fits is added. Does nothing when
  /// idle, during a postponed break or at that limit. Returns whether time was
  /// added.
  @discardableResult
  func extend(by minutes: Int) -> Bool {
    guard
      let adjustment = SessionSequence.extend(
        countdown, by: Self.seconds(forMinutes: minutes), limit: Self.sessionLimitSeconds,
        now: now())
    else { return false }
    let wasWaiting = isWaitingToContinue
    isWaitingToContinue = false
    apply(adjustment)
    if wasWaiting { startTicking() }
    saveSnapshot()
    return true
  }

  /// Puts off the running break by `minutes`: the break screen goes away and
  /// the break starts again, at its full length, once they have passed.
  func postponeBreak(minutes: Int) {
    pendingAlarm = nil
    guard
      let adjustment = SessionSequence.postpone(
        countdown, delay: Self.seconds(forMinutes: minutes), now: now())
    else { return }
    isBreakPostponed = true
    apply(adjustment)
    startTicking()
    saveSnapshot()
  }

  /// Longest a session may become through "+5 min" or "Add Time", in seconds.
  static var sessionLimitSeconds: Int {
    seconds(forMinutes: SessionDuration.minuteRange.upperBound)
  }

  /// Whether the current session already lasts the longest a session may be, so
  /// it cannot be extended (a break waiting on the break screen can).
  var isAtSessionLimit: Bool {
    state != .idle && !isWaitingToContinue && totalDuration >= Self.sessionLimitSeconds
  }

  private func refreshCanExtend() {
    let value = !isAtSessionLimit && !isBreakPostponed
    if canExtend != value { canExtend = value }
  }

  /// Length of the current session in seconds.
  var sessionLengthSeconds: Int { totalDuration }

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
    // The new instance owns the session once a relaunch began.
    guard !isRelaunching else { return }
    syncFallbackNotification()
    TimerSnapshot(
      state: state, sessionType: currentSessionType, endDate: endDate,
      remaining: timeRemaining, totalDuration: totalDuration,
      focusSessionsCompleted: focusSessionsCompleted, isBreakPostponed: isBreakPostponed,
      isWaitingToContinue: isWaitingToContinue, label: startedLabel, lastActivity: lastActivity,
      startedAt: startedAt, pausedAt: state == .paused ? pausedAt : nil,
      cycleStartedAt: cycleStartedAt, breakScreenShownAt: breakScreenShownAt
    ).save(to: defaults)
  }

  /// Picks up the session saved before the app quit. A clean quit paused it
  /// (`handleWillTerminate`), so it stays paused. A session still running in the
  /// snapshot (a crash or force quit) keeps counting from its end date. A session that
  /// ended while the app was closed is recorded in the history on the day it
  /// ended and the next session follows, without the alarm or a late
  /// notification (the one scheduled for its end showed on time), but with the
  /// daily goal notification when it took today's pomodoros up to the goal; it
  /// only starts when the session ended within
  /// `overdueGracePeriod`. A waiting break screen or a postponed break that is due
  /// is not shown at launch: the timer waits on the next session instead. A timer
  /// left idle with a stale cycle (`restartCycleIfStale`) opens on a fresh one.
  private func restore(_ snapshot: TimerSnapshot) {
    currentSessionType = snapshot.sessionType
    focusSessionsCompleted = snapshot.focusSessionsCompleted
    cycleStartedAt = snapshot.cycleStartedAt
    startedLabel = snapshot.label
    lastActivity = snapshot.lastActivity
    startedAt = snapshot.startedAt
    pausedAt = snapshot.state == .paused ? snapshot.pausedAt : nil
    defer { restartCycleIfStale() }
    resetForCurrentSession()

    switch TimerRestorePlan.make(
      from: snapshot, now: now(), autoStart: autoStart,
      keepBreakScreenOpen: keepBreakScreenOpen, breakScreenShown: breakScreenCanShow,
      overdueGracePeriod: Self.overdueGracePeriod)
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
      if isBreak, !postponed { breakScreenShownAt = snapshot.breakScreenShownAt }
      startTicking()
    case .postponedBreakDue:
      state = .idle
    case .expired(let end, let duration, let startNext):
      lastActivity = end
      let pomodorosBefore = history.totals(on: end).pomodoros
      history.recordCompletedSession(
        currentSessionType, duration: TimeInterval(duration), start: startedAt, end: end,
        label: sessionLabel(for: currentSessionType))
      sendDailyGoalNotificationIfReached(pomodorosBefore: pomodorosBefore, endedAt: end)
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
