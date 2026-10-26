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
  /// Sound after a focus session (`AlarmSound`); "None" plays nothing.
  static let alarmSound = "alarmSound"
  /// Sound after a break; unset = the same as `alarmSound`.
  static let breakEndSound = "breakEndSound"
  static let alarmVolume = "alarmVolume"
  static let notificationsEnabled = "notificationsEnabled"
  /// Mark session notifications time-sensitive so they show during a Focus mode.
  static let breakThroughFocus = "breakThroughFocus"
  static let alwaysVisible = "alwaysVisible"
  static let overlaySkipDelay = "overlaySkipDelay"
  static let backgroundColorHex = "backgroundColorHex"
  static let showProgressCircle = "showProgressCircle"
  static let hideMenuBarTime = "hideMenuBarTime"
  static let hideDockIcon = "hideDockIcon"
  static let keepAwake = "keepAwake"
  /// Pause a running session when the Mac sleeps or the screen locks (off by default).
  static let pauseOnSleep = "pauseOnSleep"
  static let overlayEnabled = "overlayEnabled"
  static let overlaySkipFullscreen = "overlaySkipFullscreen"
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
  static let hotKeyResetKeyCode = "hotKeyResetKeyCode"
  static let hotKeyResetModifiers = "hotKeyResetModifiers"
  /// The Reset shortcut is off until the user turns it on.
  static let hotKeyResetEnabled = "hotKeyResetEnabled"
  /// Pomodoros to finish per day (`DailyGoal`); 0 = no goal.
  static let dailyGoal = "dailyGoal"
  /// When the "daily goal reached" notification last went out, so it shows once a day.
  static let dailyGoalNotifiedAt = "dailyGoalNotifiedAt"
  /// Days shown in Settings → Statistics: 7 or 30 (`SessionStatistics.periodLengths`).
  static let statisticsDays = "statisticsDays"
  /// The timer's saved session (`TimerSnapshot` as JSON), restored at launch.
  static let timerSnapshot = "timerSnapshot"
}
