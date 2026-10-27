//  Created by homielab.com

import Foundation

/// Pure state machine for the skip/postpone countdown on the break overlay.
///
/// While `canSkip` is false, Skip and Postpone buttons are hidden and the overlay
/// shows "Skip available in %d". Once `remainingSeconds` hits 0, `canSkip` becomes true.
struct BreakSkipCountdown: Equatable {
  private(set) var remainingSeconds: Int
  private(set) var canSkip: Bool

  init(skipDelay: Int) {
    let clamped = BreakOverlayAccessibility.skipDelay(stored: skipDelay)
    self.remainingSeconds = clamped
    self.canSkip = clamped == 0
  }

  /// Advances the countdown by one second.
  /// Returns `true` if skip became available on this tick.
  @discardableResult
  mutating func tick() -> Bool {
    guard !canSkip else { return false }
    if remainingSeconds > 1 {
      remainingSeconds -= 1
      return false
    } else {
      remainingSeconds = 0
      canSkip = true
      return true
    }
  }

  /// Resets the countdown with a new or existing delay.
  mutating func reset(skipDelay: Int) {
    let clamped = BreakOverlayAccessibility.skipDelay(stored: skipDelay)
    self.remainingSeconds = clamped
    self.canSkip = clamped == 0
  }
}
