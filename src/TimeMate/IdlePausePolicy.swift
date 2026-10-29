//  Created by homielab.com

import Foundation

/// "Auto-pause when I'm away": a running focus session pauses once the Mac has
/// had no keyboard, mouse or trackpad input for the chosen number of minutes,
/// and the minutes away go back on the clock, so the history only counts time
/// at the desk. Breaks keep running.
enum IdlePausePolicy {
  /// The setting when off (the default).
  static let off = 0
  /// Minutes Settings offers; `off` first.
  static let choices = [off, 3, 5, 10]
  /// Stored values outside `choices` are clamped into this range.
  static let validRange = 1...60
  /// Earliest next look at the idle time while a focus session runs.
  static let minimumCheckDelay: TimeInterval = 1
  /// How often a session paused while away looks for the user coming back.
  static let returnCheckInterval: TimeInterval = 2
  /// Idle for less than this: someone just used the keyboard, mouse or trackpad.
  static let backWithin: TimeInterval = 5

  /// The stored minutes; `off` when unset, zero or negative.
  static func sanitized(_ stored: Int?) -> Int {
    guard let stored, stored > off else { return off }
    return min(max(stored, validRange.lowerBound), validRange.upperBound)
  }

  /// Seconds without input after which a focus session pauses; `nil` when off.
  /// Debug builds count minutes as seconds, like the session lengths.
  static func threshold(minutes: Int) -> TimeInterval? {
    let minutes = sanitized(minutes)
    guard minutes != off else { return nil }
    return TimeInterval(PomodoroTimer.seconds(forMinutes: minutes))
  }

  /// Whether the running session pauses: only a focus session, and only once
  /// the user has been away for `threshold` seconds.
  static func shouldPause(
    state: PomodoroState, isBreak: Bool, idleSeconds: TimeInterval, threshold: TimeInterval?
  ) -> Bool {
    guard let threshold else { return false }
    return state == .active && !isBreak && idleSeconds >= threshold
  }

  /// Seconds left once the time away is given back: the time left now plus the
  /// idle time, but never more than the session ran since it last started or
  /// resumed (`runningFor`), nor more than the session's length.
  static func remainingAfterAway(
    secondsLeft: TimeInterval, idleSeconds: TimeInterval, runningFor: TimeInterval,
    totalDuration: Int
  ) -> Int {
    let givenBack = max(0, min(idleSeconds, runningFor))
    let left = Int((secondsLeft + givenBack).rounded())
    return min(left, totalDuration)
  }

  /// When to look at the idle time again: the user can't reach `threshold`
  /// sooner than `threshold - idleSeconds` from now.
  static func nextCheckDelay(idleSeconds: TimeInterval, threshold: TimeInterval) -> TimeInterval {
    max(minimumCheckDelay, threshold - idleSeconds)
  }

  /// Whether the keyboard, mouse or trackpad was just used.
  static func userIsBack(idleSeconds: TimeInterval) -> Bool {
    idleSeconds < backWithin
  }
}
