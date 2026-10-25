//  Created by homielab.com

import Foundation

/// Limits and parsing for the session lengths set in Settings → Durations.
enum SessionDuration {
  /// Any whole number of minutes in this range can be entered, e.g. 50/10 or 90.
  static let minuteRange = 1...180

  /// The minutes typed by the user, or `nil` when the text is not a whole
  /// number within `minuteRange`.
  static func minutes(from text: String) -> Int? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Int(trimmed), minuteRange.contains(value) else { return nil }
    return value
  }

  /// A stored session length made safe to run: at least one minute, so a zero or
  /// negative value in the defaults (edited by hand or left by an old version)
  /// can't end every session the moment it starts. Longer values are kept, the
  /// upper limit only applies to what can be entered in Settings.
  static func sanitized(_ minutes: Int) -> Int {
    max(minutes, minuteRange.lowerBound)
  }
}
