//  Created by homielab.com

import AppKit
import Foundation

/// Accessibility and layout decisions of the break overlay, kept free of
/// windows and views so they can be tested.
enum BreakOverlayAccessibility {
  /// What VoiceOver announces when a break starts, e.g. "Break started, 5 minutes".
  /// The minutes are rounded up so a break never sounds shorter than it is.
  static func announcement(secondsRemaining: Int) -> String {
    let minutes = max(1, (secondsRemaining + 59) / 60)
    if minutes == 1 {
      return NSLocalizedString("Break started, 1 minute", comment: "VoiceOver announcement")
    }
    return String(
      format: NSLocalizedString("Break started, %d minutes", comment: "VoiceOver announcement"),
      minutes)
  }

  /// Spoken value of the break countdown, e.g. "4 minutes, 30 seconds".
  static func countdownValue(secondsRemaining: Int) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .full
    formatter.allowedUnits = secondsRemaining >= 60 ? [.minute, .second] : [.second]
    formatter.zeroFormattingBehavior = .dropAll
    return formatter.string(from: TimeInterval(max(0, secondsRemaining)))
      ?? secondsRemaining.toMinuteSecondString()
  }

  /// The overlay window that gets focus and the animation: the one on the
  /// screen the user is working on (`NSScreen.main`), or the first screen.
  static func primaryScreenIndex(screens: [CGRect], main: CGRect?) -> Int {
    guard let main, let index = screens.firstIndex(of: main) else { return 0 }
    return index
  }

  /// Fade length of the overlay windows; none when Reduce Motion is on.
  static func fadeDuration(reduceMotion: Bool) -> TimeInterval? {
    reduceMotion ? nil : 1.5
  }

  /// Minutes the break screen offers to postpone the break by.
  static let postponeOptions = [1, 3, 5]
  /// Minutes the "+5 min" button adds to the break.
  static let extendMinutes = 5

  /// VoiceOver label of a postpone button, e.g. "Postpone break by 3 minutes".
  static func postponeLabel(minutes: Int) -> String {
    if minutes == 1 {
      return NSLocalizedString("Postpone break by 1 minute", comment: "VoiceOver label")
    }
    return String(
      format: NSLocalizedString("Postpone break by %d minutes", comment: "VoiceOver label"),
      minutes)
  }

  /// Seconds before the Skip button shows (Settings, 0–30 s). The default is 5.
  static let skipDelayRange = 0...30
  static let defaultSkipDelay = 5

  /// The stored skip delay clamped to `skipDelayRange`; the default if unset.
  static func skipDelay(stored: Any?) -> Int {
    guard let seconds = stored as? Int else { return defaultSkipDelay }
    return min(max(seconds, skipDelayRange.lowerBound), skipDelayRange.upperBound)
  }

  static var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }
}
