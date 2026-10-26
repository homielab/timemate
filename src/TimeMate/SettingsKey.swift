//  Created by homielab.com

/// Keys of the user-defaults-backed settings, shared by the settings UI, the
/// app delegate and the timer, so they can never drift apart on the raw strings.
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
  static let backgroundColorHex = "backgroundColorHex"
  static let showProgressCircle = "showProgressCircle"
  static let hideMenuBarTime = "hideMenuBarTime"
  static let hideDockIcon = "hideDockIcon"
  static let keepAwake = "keepAwake"
  static let overlayEnabled = "overlayEnabled"
  static let autoStartOnLaunch = "autoStartOnLaunch"
  /// Open the popover also when the app starts at login (off by default).
  static let showTimerAtLogin = "showTimerAtLogin"
  /// Set once the app has started; its absence marks the first launch.
  static let hasLaunchedBefore = "hasLaunchedBefore"
  static let hotKeyStartPauseKeyCode = "hotKeyStartPauseKeyCode"
  static let hotKeyStartPauseModifiers = "hotKeyStartPauseModifiers"
  static let hotKeyStartPauseEnabled = "hotKeyStartPauseEnabled"
  static let hotKeySkipKeyCode = "hotKeySkipKeyCode"
  static let hotKeySkipModifiers = "hotKeySkipModifiers"
  static let hotKeySkipEnabled = "hotKeySkipEnabled"
  /// The timer's saved session (`TimerSnapshot` as JSON), restored at launch.
  static let timerSnapshot = "timerSnapshot"
}
