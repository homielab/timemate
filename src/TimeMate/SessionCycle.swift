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
  /// How long the timer may sit idle across midnight before the cycle starts
  /// over: a short break that crosses midnight keeps the cycle.
  static let dayChangeGap: TimeInterval = 60 * 60

  /// Whether the focus sessions counted towards the long break are too old to
  /// count: the last session began or ended more than `staleAfter` before
  /// `now`, or on another calendar day (in `calendar`'s time zone) and more
  /// than `dayChangeGap` before `now` — last night versus this morning, while
  /// pomodoros either side of midnight still make one cycle. No known activity
  /// (`nil`) is stale too. A clock set back is not.
  static func isStale(lastActivity: Date?, now: Date, calendar: Calendar) -> Bool {
    guard let lastActivity else { return true }
    let gap = now.timeIntervalSince(lastActivity)
    if gap > staleAfter { return true }
    return gap > dayChangeGap && !calendar.isDate(lastActivity, inSameDayAs: now)
  }

  /// `stored` clamped to `validRange`; a missing value gives the default.
  static func sanitizedInterval(_ stored: Int?) -> Int {
    guard let stored else { return defaultInterval }
    return min(max(stored, validRange.lowerBound), validRange.upperBound)
  }

  /// The interval Settings shows for a stored value: what the timer runs,
  /// e.g. 8 for a stored 12 and 1 for a stored 0.
  static func displayInterval(_ stored: Int) -> Int {
    sanitizedInterval(stored)
  }

  /// VoiceOver value of the Cycles stepper, e.g. "4 focus sessions".
  static func settingsAccessibilityValue(_ interval: Int) -> String {
    String.localizedStringWithFormat(
      NSLocalizedString("%lld focus sessions", comment: "Cycles stepper in Settings"),
      interval)
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
