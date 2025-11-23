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

  // MARK: - AppStorage Settings
  @AppStorage("focusDuration") private var focusDurationMinutes = 25
  @AppStorage("shortBreakDuration") private var shortBreakDurationMinutes = 5
  @AppStorage("longBreakDuration") private var longBreakDurationMinutes = 15
  @AppStorage("longBreakInterval") private var longBreakInterval = 4
  @AppStorage("autoStartNextSession") private var autoStartNextSession = true
  @AppStorage("alarmSound") private var alarmSound = "Glass"
  @AppStorage("alarmVolume") private var alarmVolume: Double = 1.0

  // MARK: - Private Properties
  var cancellables = Set<AnyCancellable>()
  private var timer: AnyCancellable?
  private var totalDuration: Int = 0

  init() {
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
        guard let self = self else { return }
        if self.timeRemaining > 0 {
          self.timeRemaining -= 1
          self.progress = Double(self.timeRemaining) / Double(max(1, self.totalDuration))
        } else {
          self.timer?.cancel()
          self.playSound(named: self.alarmSound)
          self.sendNotification()
          self.advanceToNextSession()
        }
      }
  }

  func pauseTimer() {
    state = .paused
    timer?.cancel()
  }

  func stopTimer() {
    state = .idle
    timer?.cancel()
    resetForCurrentSession()
  }

  func skipSession() {
    timer?.cancel()
    advanceToNextSession()
  }

  func restartCycle() {
    state = .idle
    focusSessionsCompleted = 0
    currentSessionType = .focus
    timer?.cancel()
    resetForCurrentSession()
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

  @AppStorage("notificationsEnabled") private var notificationsEnabled = true

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
