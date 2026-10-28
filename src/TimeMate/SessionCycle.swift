//  Created by homielab.com

import Foundation

/// The number of focus sessions before a long break ("Cycles" in Settings).
enum SessionCycle {
  static let defaultInterval = 4
  /// What Settings offers.
  static let settingsRange = 2...8
  /// What the timer accepts from defaults; anything else is clamped into it.
  static let validRange = 1...8

  /// How long the timer may sit idle before the cycle starts over.
  static let staleAfter: TimeInterval = 4 * 60 * 60

  /// Whether the focus sessions counted towards the long break are too old to
  /// count: the last session began or ended on another calendar day (in
  /// `calendar`'s time zone) or more than `staleAfter` before `now`. No known
  /// activity (`nil`) is stale too. A clock set back is not.
  static func isStale(lastActivity: Date?, now: Date, calendar: Calendar) -> Bool {
    guard let lastActivity else { return true }
    if !calendar.isDate(lastActivity, inSameDayAs: now) { return true }
    return now.timeIntervalSince(lastActivity) > staleAfter
  }

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

  /// VoiceOver label and value of the popover clock. The label is fixed so it is
  /// not re-announced every second; the value is spelled out, e.g.
  /// "4 minutes, 30 seconds" (with "75% remaining" when the progress ring is shown).
  static func clockAccessibility(secondsRemaining: Int, progress: Double?) -> (
    label: String, value: String
  ) {
    var value = BreakOverlayAccessibility.countdownValue(secondsRemaining: secondsRemaining)
    if let progress {
      value += ", " + progressAccessibilityValue(progress)
    }
    return (NSLocalizedString("Time remaining", comment: "Popover clock, VoiceOver"), value)
  }
}
