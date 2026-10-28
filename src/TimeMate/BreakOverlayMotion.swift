//  Created by homielab.com

import Foundation

/// What keeps moving on the break screen. A finished break that waits for Continue Work
/// can stay up for hours while nobody is at the Mac, so it stops the cat and ticks the
/// clock once a minute instead of once a second.
enum BreakOverlayMotion {
  /// The cat plays only during the break itself, and never with Reduce Motion.
  static func animatesCat(reduceMotion: Bool, isWaitingToContinue: Bool) -> Bool {
    !reduceMotion && !isWaitingToContinue
  }

  /// Seconds between wall-clock ticks while the timer is not active. The clock shows
  /// hours and minutes only; the countdown needs seconds while the break is paused.
  static func clockInterval(isWaitingToContinue: Bool) -> TimeInterval {
    isWaitingToContinue ? 60 : 1
  }

  /// The first tick after `date`, on a whole multiple of `interval`, so a once-a-minute
  /// clock turns over when the minute does.
  static func nextTick(after date: Date, interval: TimeInterval) -> Date {
    let seconds = date.timeIntervalSinceReferenceDate
    let next = (seconds / interval).rounded(.down) * interval + interval
    return Date(timeIntervalSinceReferenceDate: next)
  }
}
