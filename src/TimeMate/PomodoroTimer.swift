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

  init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }) {
    self.defaults = defaults
    self.now = now
    resetForCurrentSession()

    #if DEBUG
      print("--- TimeMate running in DEBUG mode (timers are in seconds) ---")
    #endif
  }

  func startTimer() {
    if state != .paused {
      resetForCurrentSession()
    }
    state = .active

    timer = Timer.publish(every: 1, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        self?.handleTick()
      }
  }

  /// One tick of the state machine: count the session down and, at zero, finish
  /// it. Internal so tests can drive ticks without waiting on real timers.
  func handleTick() {
    lastTickAt = now()

    if timeRemaining > 0 {
      timeRemaining -= 1
      progress = Double(timeRemaining) / Double(max(1, totalDuration))
    } else {
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

  func pauseTimer() {
    state = .paused
    timer?.cancel()
  }

  func stopTimer() {
    isWaitingToContinue = false
    state = .idle
    timer?.cancel()
    resetForCurrentSession()
  }

  func skipSession() {
    isWaitingToContinue = false
    timer?.cancel()
    advanceToNextSession()
  }

  func restartCycle() {
    isWaitingToContinue = false
    state = .idle
    focusSessionsCompleted = 0
    currentSessionType = .focus
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
    print("DEBUG: Firing notification for session \(currentSessionType.rawValue)...")

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
