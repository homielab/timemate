//  Created by homielab.com

import Foundation

/// The settings `PomodoroTimer` reads live from its defaults.
extension PomodoroTimer {
  var focusDurationMinutes: Int {
    defaults.object(forKey: SettingsKey.focusDuration) as? Int ?? 25
  }
  var shortBreakDurationMinutes: Int {
    defaults.object(forKey: SettingsKey.shortBreakDuration) as? Int ?? 5
  }
  var longBreakDurationMinutes: Int {
    defaults.object(forKey: SettingsKey.longBreakDuration) as? Int ?? 15
  }
  var longBreakInterval: Int {
    SessionCycle.sanitizedInterval(defaults.object(forKey: SettingsKey.longBreakInterval) as? Int)
  }
  var autoStartNextSession: Bool {
    defaults.object(forKey: SettingsKey.autoStartNextSession) as? Bool ?? true
  }
  var keepBreakScreenOpen: Bool {
    defaults.object(forKey: SettingsKey.keepBreakScreenOpen) as? Bool ?? true
  }
  var alarmVolume: Double {
    defaults.object(forKey: SettingsKey.alarmVolume) as? Double ?? 1.0
  }
  var notificationsEnabled: Bool {
    defaults.object(forKey: SettingsKey.notificationsEnabled) as? Bool ?? true
  }
  var breakThroughFocus: Bool {
    defaults.object(forKey: SettingsKey.breakThroughFocus) as? Bool ?? true
  }
  var dailyGoal: Int {
    DailyGoal.sanitized(defaults.object(forKey: SettingsKey.dailyGoal) as? Int)
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

  func durationFor(session: SessionType) -> Int {
    let stored: Int
    switch session {
    case .focus: stored = focusDurationMinutes
    case .shortBreak: stored = shortBreakDurationMinutes
    case .longBreak: stored = longBreakDurationMinutes
    }
    return Self.seconds(forMinutes: SessionDuration.sanitized(stored))
  }
}
