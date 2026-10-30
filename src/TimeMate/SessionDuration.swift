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
    guard let value = Int(trimmed) else {
      // A whole number too big for `Int` is still a whole number, just out of range.
      guard isWholeNumber(trimmed) else { return .notANumber }
      return trimmed.hasPrefix("-") ? .tooShort : .tooLong
    }
    return value < minuteRange.lowerBound ? .tooShort : .tooLong
  }

  /// Digits with an optional leading sign, the text `Int(_:)` accepts when it fits.
  private static func isWholeNumber(_ text: String) -> Bool {
    let digits = text.first == "-" || text.first == "+" ? text.dropFirst() : Substring(text)
    return !digits.isEmpty && digits.allSatisfy { $0.isASCII && $0.isNumber }
  }

  /// The bounds the timer keeps a stored length in when it reads it. Stored
  /// lengths are brought into `minuteRange` at launch and when Settings opens
  /// (`clampStored(in:)`); this wider bound only guards a value written with
  /// `defaults write` while the app runs, so converting it to seconds can't overflow.
  static let storedMinuteRange = minuteRange.lowerBound...1440

  /// A stored session length made safe to run, clamped to `storedMinuteRange`: a
  /// zero or negative value can't end every session the moment it starts, and a
  /// huge one can't crash the app.
  static func sanitized(_ minutes: Int) -> Int {
    min(max(minutes, storedMinuteRange.lowerBound), storedMinuteRange.upperBound)
  }

  /// A stored length as Settings shows it and `clampStored(in:)` saves it: within
  /// `minuteRange`, e.g. 180 for a stored 240 and 1 for a stored 0.
  static func clamped(_ minutes: Int) -> Int {
    min(max(minutes, minuteRange.lowerBound), minuteRange.upperBound)
  }

  /// The defaults keys of the focus, short break and long break lengths.
  static let keys = [
    SettingsKey.focusDuration, SettingsKey.shortBreakDuration, SettingsKey.longBreakDuration,
  ]

  /// Saves each stored length outside `minuteRange` (left by an older version
  /// or set with `defaults write`) as `clamped(_:)`, so Settings and the timer
  /// agree. A missing length stays missing (the default applies).
  static func clampStored(in defaults: UserDefaults) {
    for key in keys {
      guard let stored = defaults.object(forKey: key) as? Int else { continue }
      let value = clamped(stored)
      if value != stored { defaults.set(value, forKey: key) }
    }
  }
}
