//  Created by homielab.com

import AppKit

/// Whether the popover opens by itself when the app starts.
///
/// A launch at login stays quiet so TimeMate never takes focus from what the
/// user opens first; the very first launch and a launch by hand show the timer.
enum LaunchBehavior {
  static func showsPopover(isFirstLaunch: Bool, isLoginLaunch: Bool, showTimerAtLogin: Bool)
    -> Bool
  {
    isFirstLaunch || !isLoginLaunch || showTimerAtLogin
  }

  /// Whether "Auto-start on launch" starts a session now. Only a focus session
  /// starts: a restored break (or one waiting for a click) is left for the user,
  /// so opening the Mac never puts the break screen over their work.
  static func shouldAutoStartOnLaunch(
    enabled: Bool, state: PomodoroState, sessionType: SessionType, isWaiting: Bool
  ) -> Bool {
    enabled && state == .idle && sessionType == .focus && !isWaiting
  }

  /// Whether `event` (the Apple event that opened the app) comes from the
  /// login item: macOS marks it with `keyAELaunchedAsLogInItem`.
  static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
    guard let event, event.eventID == kAEOpenApplication else { return false }
    return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
      == keyAELaunchedAsLogInItem
  }
}
