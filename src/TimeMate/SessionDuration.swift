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

  /// Why a typed entry can't be saved. The raw value is the localization key of
  /// the message shown and read by VoiceOver.
  enum Problem: String, Equatable {
    case empty = "Empty. Enter 1–180 minutes."
    case notANumber = "Not a whole number. Enter 1–180 minutes."
    case tooShort = "Too short. Enter at least 1 minute."
    case tooLong = "Too long. Enter at most 180 minutes."
  }

  /// What is wrong with the typed text, or `nil` when `minutes(from:)` accepts it.
  static func validationHint(for text: String) -> Problem? {
    if minutes(from: text) != nil { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .empty }
    guard let value = Int(trimmed) else { return .notANumber }
    return value < minuteRange.lowerBound ? .tooShort : .tooLong
  }

  /// A stored session length made safe to run: at least one minute, so a zero or
  /// negative value in the defaults (edited by hand or left by an old version)
  /// can't end every session the moment it starts. Longer values are kept, the
  /// upper limit only applies to what can be entered in Settings.
  static func sanitized(_ minutes: Int) -> Int {
    max(minutes, minuteRange.lowerBound)
  }
}
