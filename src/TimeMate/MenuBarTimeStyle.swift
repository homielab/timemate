//  Created by homielab.com

import Foundation

/// What the menu bar item shows next to its icon.
enum MenuBarTimeStyle: String, CaseIterable {
  /// "12:34", redrawn every second.
  case minutesSeconds
  /// "13m" (minutes left, rounded up), redrawn once a minute.
  case minutesOnly
  /// Just the icon.
  case iconOnly

  var showsTime: Bool { self != .iconOnly }

  /// The text beside the icon; empty for `.iconOnly`.
  func text(seconds: Int) -> String {
    switch self {
    case .minutesSeconds: return seconds.toMinuteSecondString()
    case .minutesOnly: return "\(Self.minutes(roundingUp: seconds))m"
    case .iconOnly: return ""
    }
  }

  static func minutes(roundingUp seconds: Int) -> Int {
    (max(0, seconds) + 59) / 60
  }

  /// Seconds until the minutes shown by `.minutesOnly` change for a session with
  /// `remaining` seconds left; in (0, 60], or 0 when nothing is left.
  static func secondsUntilMinuteChange(remaining: TimeInterval) -> TimeInterval {
    guard remaining > 0 else { return 0 }
    let minutesShown = (remaining / 60).rounded(.up)
    return remaining - 60 * (minutesShown - 1)
  }

  /// The style to use, given the stored one and the old "hide time" switch.
  static func resolved(stored: String?, legacyHide: Bool) -> MenuBarTimeStyle {
    if let stored, let style = MenuBarTimeStyle(rawValue: stored) { return style }
    return legacyHide ? .iconOnly : .minutesSeconds
  }

  /// One-time migration: writes `menuBarTimeStyle` from the old `hideMenuBarTime`
  /// switch. The old key stays, so nothing that reads it breaks.
  static func migrate(_ defaults: UserDefaults = .standard) {
    let stored = defaults.string(forKey: SettingsKey.menuBarTimeStyle)
    let style = resolved(
      stored: stored, legacyHide: defaults.bool(forKey: SettingsKey.hideMenuBarTime))
    if stored != style.rawValue {
      defaults.set(style.rawValue, forKey: SettingsKey.menuBarTimeStyle)
    }
  }

  static func current(_ defaults: UserDefaults = .standard) -> MenuBarTimeStyle {
    resolved(
      stored: defaults.string(forKey: SettingsKey.menuBarTimeStyle),
      legacyHide: defaults.bool(forKey: SettingsKey.hideMenuBarTime))
  }
}
