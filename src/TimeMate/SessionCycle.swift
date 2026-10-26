//  Created by homielab.com

import Foundation

/// The number of focus sessions before a long break ("Cycles" in Settings).
enum SessionCycle {
  static let defaultInterval = 4
  /// What Settings offers.
  static let settingsRange = 2...8
  /// What the timer accepts from defaults; anything else is clamped into it.
  static let validRange = 1...8

  /// `stored` clamped to `validRange`; a missing value gives the default.
  static func sanitizedInterval(_ stored: Int?) -> Int {
    guard let stored else { return defaultInterval }
    return min(max(stored, validRange.lowerBound), validRange.upperBound)
  }

  /// VoiceOver text for the cycle dots, e.g. "2 of 4 focus sessions done", or
  /// "Long break" while the cup icon is shown.
  static func accessibilityLabel(completed: Int, total: Int, isLongBreak: Bool) -> String {
    if isLongBreak {
      return NSLocalizedString("Long Break", comment: "The name of the current session type")
    }
    let total = sanitizedInterval(total)
    return String(
      format: NSLocalizedString(
        "%1$lld of %2$lld focus sessions done", comment: "Cycle dots in the popover"),
      min(max(completed, 0), total), total)
  }

  /// VoiceOver value of the progress ring: the share of the session left,
  /// e.g. "75% remaining".
  static func progressAccessibilityValue(_ progress: Double) -> String {
    let percent = Int((min(max(progress, 0), 1) * 100).rounded())
    return String(
      format: NSLocalizedString("%lld%% remaining", comment: "Progress ring in the popover"),
      percent)
  }
}
