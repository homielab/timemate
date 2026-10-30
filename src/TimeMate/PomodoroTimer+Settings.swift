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
  var autoStart: AutoStart { AutoStart(defaults: defaults) }
  var keepBreakScreenOpen: Bool {
    defaults.object(forKey: SettingsKey.keepBreakScreenOpen) as? Bool ?? true
  }
  /// Whether a break screen would appear now: it is switched on and no full-screen
  /// app holds it back. Only then does a finished break wait on it.
  var breakScreenCanShow: Bool {
    OverlayPolicy.breakScreenCanShow(
      settings: OverlaySettings(
        enabled: defaults.object(forKey: SettingsKey.overlayEnabled) as? Bool ?? true,
        skipFullscreen: defaults.object(forKey: SettingsKey.overlaySkipFullscreen) as? Bool ?? true),
      isFrontmostFullscreen: isFullscreenProbe)
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
  /// The label of the focus session, typed in the popover; `nil` when empty.
  var sessionLabel: String? {
    SessionLabel.normalized(defaults.string(forKey: SettingsKey.sessionLabel))
  }
  /// The label to record for the session that ran: the one captured when it began,
  /// or the label field as it stands when it began without one (`LabelAssignment`).
  func sessionLabel(for sessionType: SessionType) -> String? {
    guard sessionType == .focus else { return nil }
    return LabelAssignment.label(started: startedLabel, field: sessionLabel)
  }
  /// What editing the label field does right now.
  var labelCaption: LabelAssignment.Caption {
    LabelAssignment.caption(
      inFocusSession: currentSessionType == .focus && state != .idle, started: startedLabel)
  }
  var dailyGoal: Int {
    DailyGoal.sanitized(defaults.object(forKey: SettingsKey.dailyGoal) as? Int)
  }
  var streakSkipsWeekends: Bool { defaults.bool(forKey: SettingsKey.streakSkipsWeekends) }

  /// Seconds in `minutes` of session time. Debug builds treat minutes as
  /// seconds so sessions can be tried out quickly.
  static func seconds(forMinutes minutes: Int) -> Int {
    #if DEBUG
      return minutes
    #else
      return minutes * 60
    #endif
  }

  /// The stored length of `session` in minutes.
  func minutesFor(session: SessionType) -> Int {
    switch session {
    case .focus: return focusDurationMinutes
    case .shortBreak: return shortBreakDurationMinutes
    case .longBreak: return longBreakDurationMinutes
    }
  }

  func durationFor(session: SessionType) -> Int {
    Self.seconds(forMinutes: SessionDuration.sanitized(minutesFor(session: session)))
  }
}
