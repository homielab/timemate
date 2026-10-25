//  Created by homielab.com

/// Keys of the user-defaults-backed settings that both the UI (ContentView) and
/// the timer (PomodoroTimer) read or write, so the two sides can never drift
/// apart on the raw key strings.
enum SettingsKey {
  static let focusDuration = "focusDuration"
  static let shortBreakDuration = "shortBreakDuration"
  static let longBreakDuration = "longBreakDuration"
  static let longBreakInterval = "longBreakInterval"
  static let autoStartNextSession = "autoStartNextSession"
  static let keepBreakScreenOpen = "keepBreakScreenOpen"
  static let alarmSound = "alarmSound"
  static let alarmVolume = "alarmVolume"
  static let notificationsEnabled = "notificationsEnabled"
  static let alwaysVisible = "alwaysVisible"
  static let overlaySkipDelay = "overlaySkipDelay"
  static let hotKeyStartPauseKeyCode = "hotKeyStartPauseKeyCode"
  static let hotKeyStartPauseModifiers = "hotKeyStartPauseModifiers"
  static let hotKeyStartPauseEnabled = "hotKeyStartPauseEnabled"
  static let hotKeySkipKeyCode = "hotKeySkipKeyCode"
  static let hotKeySkipModifiers = "hotKeySkipModifiers"
  static let hotKeySkipEnabled = "hotKeySkipEnabled"
}
