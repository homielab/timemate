//  Created by homielab.com

import AVFoundation
import AppKit
import Combine
import SwiftUI
import UserNotifications

enum SessionType: String, CaseIterable, Codable {
  case focus = "Focus"
  case shortBreak = "Short Break"
  case longBreak = "Long Break"
}

enum PomodoroState: String, Codable {
  case idle, active, paused
}

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
  private let defaults: UserDefaults
  /// Source of wall-clock time; tests inject a fixed clock.
  private let now: () -> Date
  /// Log of completed sessions behind the "Today" statistics.
  let history: SessionHistory

  private var focusDurationMinutes: Int {
    defaults.object(forKey: SettingsKey.focusDuration) as? Int ?? 25
  }
  private var shortBreakDurationMinutes: Int {
    defaults.object(forKey: SettingsKey.shortBreakDuration) as? Int ?? 5
  }
  private var longBreakDurationMinutes: Int {
    defaults.object(forKey: SettingsKey.longBreakDuration) as? Int ?? 15
  }
  private var longBreakInterval: Int {
    defaults.object(forKey: SettingsKey.longBreakInterval) as? Int ?? 4
  }
  private var autoStartNextSession: Bool {
    defaults.object(forKey: SettingsKey.autoStartNextSession) as? Bool ?? true
  }
  private var keepBreakScreenOpen: Bool {
    defaults.object(forKey: SettingsKey.keepBreakScreenOpen) as? Bool ?? true
  }
  private var alarmSound: String {
    defaults.object(forKey: SettingsKey.alarmSound) as? String ?? "Glass"
  }
  private var alarmVolume: Double {
    defaults.object(forKey: SettingsKey.alarmVolume) as? Double ?? 1.0
  }
  private var notificationsEnabled: Bool {
    defaults.object(forKey: SettingsKey.notificationsEnabled) as? Bool ?? true
  }

  // MARK: - Private Properties
  var cancellables = Set<AnyCancellable>()
  private var timer: AnyCancellable?
  private var totalDuration: Int = 0
  /// When the latest tick fired, per `now`; lets tests verify the injected clock.
  private(set) var lastTickAt: Date?
  /// Wall-clock moment the running session ends. The remaining time is always
  /// derived from it, so sleep, App Nap or late timer fires cannot stretch a
  /// session. `nil` unless the timer is active.
  private(set) var endDate: Date?

  init(
    defaults: UserDefaults = .standard,
    now: @escaping () -> Date = { Date() },
    workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    history: SessionHistory = SessionHistory(fileURL: nil)
  ) {
    self.defaults = defaults
    self.now = now
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

  /// Fires `handleTick` every second to refresh the menu bar countdown.
  private func startTicking() {
    timer?.cancel()
    timer = Timer.publish(every: 1, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        self?.handleTick()
      }
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
      history.recordCompletedSession(
        currentSessionType, duration: TimeInterval(totalDuration), end: endDate)
      playSound(named: alarmSound)
      sendNotification()

      if keepBreakScreenOpen,
        currentSessionType == .shortBreak || currentSessionType == .longBreak
      {
        isWaitingToContinue = true
        state = .idle
      } else {
        advanceToNextSession()
      }
      saveSnapshot()
    }
  }

  /// The Mac is about to sleep: stop the ticking loop. `endDate` keeps counting
  /// in wall-clock time while the Mac sleeps.
  func handleWillSleep() {
    guard state == .active else { return }
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
    if !autoStartNextSession {
      startTimer()
    }
  }

  /// Moves on to the session after the current one and starts it when
  /// `start` (by default the "Auto-start next session" setting) is on.
  private func advanceToNextSession(start: Bool? = nil) {
    if currentSessionType == .focus {
      focusSessionsCompleted += 1
      if focusSessionsCompleted >= longBreakInterval {
        currentSessionType = .longBreak
        focusSessionsCompleted = 0
      } else {
        currentSessionType = .shortBreak
      }
    } else {
      currentSessionType = .focus
    }
    resetForCurrentSession()
    if start ?? autoStartNextSession {
      startTimer()
    } else {
      state = .idle
    }
  }

  /// Whether the current session is a break.
  var isBreak: Bool {
    currentSessionType == .shortBreak || currentSessionType == .longBreak
  }

  /// Adds `minutes` to the running break ("+5 min" on the break screen). A
  /// break that already ended and waits on the break screen starts again for
  /// `minutes`. Does nothing during focus or a postponed break.
  func extend(by minutes: Int) {
    guard minutes > 0, isBreak, !isBreakPostponed else { return }
    defer { saveSnapshot() }
    let extra = Self.seconds(forMinutes: minutes)
    if isWaitingToContinue {
      isWaitingToContinue = false
      totalDuration = extra
      timeRemaining = extra
      progress = 1.0
      state = .active
      endDate = now().addingTimeInterval(TimeInterval(extra))
      startTicking()
      return
    }
    switch state {
    case .active:
      guard let endDate else { return }
      let newEndDate = endDate.addingTimeInterval(TimeInterval(extra))
      self.endDate = newEndDate
      totalDuration += extra
      timeRemaining = max(0, Int(newEndDate.timeIntervalSince(now()).rounded()))
    case .paused:
      totalDuration += extra
      timeRemaining += extra
    case .idle:
      return
    }
    progress = Double(timeRemaining) / Double(max(1, totalDuration))
  }

  /// Puts off the running break by `minutes`: the break screen goes away and
  /// the break starts again, at its full length, once they have passed.
  func postponeBreak(minutes: Int) {
    guard minutes > 0, isBreak, state == .active, !isBreakPostponed else { return }
    defer { saveSnapshot() }
    let delay = Self.seconds(forMinutes: minutes)
    isBreakPostponed = true
    totalDuration = delay
    timeRemaining = delay
    progress = 1.0
    endDate = now().addingTimeInterval(TimeInterval(delay))
    startTicking()
  }

  /// Seconds in `minutes` of session time. Debug builds treat minutes as
  /// seconds so sessions can be tried out quickly.
  static func seconds(forMinutes minutes: Int) -> Int {
    #if DEBUG
      return minutes
    #else
      return minutes * 60
    #endif
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
    let launchTime = now()

    switch snapshot.state {
    case .idle:
      if snapshot.isWaitingToContinue {
        advanceToNextSession(start: false)
      }
    case .paused:
      isBreakPostponed = snapshot.isBreakPostponed
      totalDuration = snapshot.totalDuration
      timeRemaining = min(snapshot.remaining, totalDuration)
      progress = Double(timeRemaining) / Double(max(1, totalDuration))
      state = .paused
    case .active:
      guard var savedEndDate = snapshot.endDate else { return }
      if savedEndDate > launchTime {
        isBreakPostponed = snapshot.isBreakPostponed
        totalDuration = snapshot.totalDuration
        // A clock set back while the app was closed cannot stretch the session.
        let latestEnd = launchTime.addingTimeInterval(TimeInterval(totalDuration))
        savedEndDate = min(savedEndDate, latestEnd)
        endDate = savedEndDate
        timeRemaining = max(0, Int(savedEndDate.timeIntervalSince(launchTime).rounded()))
        progress = Double(timeRemaining) / Double(max(1, totalDuration))
        state = .active
        startTicking()
      } else if snapshot.isBreakPostponed {
        // The postponed break is due; it waits at full length for Start.
        state = .idle
      } else {
        history.recordCompletedSession(
          currentSessionType, duration: TimeInterval(snapshot.totalDuration),
          end: savedEndDate)
        let waitsOnBreakScreen = isBreak && keepBreakScreenOpen
        advanceToNextSession(start: autoStartNextSession && !waitsOnBreakScreen)
      }
    }
  }

  private func resetForCurrentSession() {
    isBreakPostponed = false
    self.totalDuration = durationFor(session: currentSessionType)
    self.timeRemaining = totalDuration
    self.progress = 1.0
  }

  private func durationFor(session: SessionType) -> Int {
    let stored: Int
    switch session {
    case .focus: stored = focusDurationMinutes
    case .shortBreak: stored = shortBreakDurationMinutes
    case .longBreak: stored = longBreakDurationMinutes
    }
    return Self.seconds(forMinutes: SessionDuration.sanitized(stored))
  }

  private func playSound(named soundName: String) {
    if let systemSound = NSSound(named: soundName) {
      systemSound.volume = Float(self.alarmVolume)
      systemSound.play()
    }
  }

  private func sendNotification() {
    guard notificationsEnabled else { return }

    let content = SessionNotification.content(forCompleted: currentSessionType)
    let request = UNNotificationRequest(
      identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  /// Runs a button tapped on the "session complete" notification.
  /// "Start Next" starts the session that follows unless it is already running
  /// (auto-start); "Skip" skips it.
  func handleNotificationAction(_ action: SessionNotificationAction) {
    switch action {
    case .startNext:
      if isWaitingToContinue {
        continueWork()
      } else if state != .active {
        startTimer()
      }
    case .skip:
      skipSession()
    }
  }
}
