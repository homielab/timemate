//  Created by homielab.com

import AVFoundation
import AppKit
import Combine
import SwiftUI
import UserNotifications

enum SessionType: String, CaseIterable {
  case focus = "Focus"
  case shortBreak = "Short Break"
  case longBreak = "Long Break"
}

enum PomodoroState {
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

  // MARK: - Settings
  // Settings are read live from the injected defaults on every use, so changes
  // made in the settings UI apply to the running timer just like @AppStorage did.
  private let defaults: UserDefaults
  /// Source of wall-clock time; tests inject a fixed clock.
  private let now: () -> Date

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
    workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
  ) {
    self.defaults = defaults
    self.now = now
    resetForCurrentSession()

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

    let remaining = max(0, Int(endDate.timeIntervalSince(tickTime).rounded()))
    if remaining > 0 {
      timeRemaining = remaining
      progress = Double(timeRemaining) / Double(max(1, totalDuration))
    } else {
      timeRemaining = 0
      progress = 0
      self.endDate = nil
      timer?.cancel()
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
  }

  func stopTimer() {
    isWaitingToContinue = false
    state = .idle
    endDate = nil
    timer?.cancel()
    resetForCurrentSession()
  }

  func skipSession() {
    isWaitingToContinue = false
    endDate = nil
    timer?.cancel()
    advanceToNextSession()
  }

  func restartCycle() {
    isWaitingToContinue = false
    state = .idle
    focusSessionsCompleted = 0
    currentSessionType = .focus
    endDate = nil
    timer?.cancel()
    resetForCurrentSession()
  }

  func continueWork() {
    isWaitingToContinue = false
    advanceToNextSession()
    if !autoStartNextSession {
      startTimer()
    }
  }

  private func advanceToNextSession() {
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
    if autoStartNextSession {
      startTimer()
    } else {
      state = .idle
    }
  }

  private func resetForCurrentSession() {
    self.totalDuration = durationFor(session: currentSessionType)
    self.timeRemaining = totalDuration
    self.progress = 1.0
  }

  private func durationFor(session: SessionType) -> Int {
    let minutes: Int
    switch session {
    case .focus: minutes = focusDurationMinutes
    case .shortBreak: minutes = shortBreakDurationMinutes
    case .longBreak: minutes = longBreakDurationMinutes
    }
    #if DEBUG
      return minutes
    #else
      return minutes * 60
    #endif
  }

  private func playSound(named soundName: String) {
    if let systemSound = NSSound(named: soundName) {
      systemSound.volume = Float(self.alarmVolume)
      systemSound.play()
    }
  }

  private func sendNotification() {
    guard notificationsEnabled else { return }

    let content = UNMutableNotificationContent()
    content.title = "TimeMate"

    let localizedSessionTitle = NSLocalizedString(
      currentSessionType.rawValue, comment: "The name of the current session type")

    content.subtitle = String(
      format: NSLocalizedString("%@ session complete!", comment: "Notification format string"),
      localizedSessionTitle
    )

    content.sound = .default
    let request = UNNotificationRequest(
      identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }
}
