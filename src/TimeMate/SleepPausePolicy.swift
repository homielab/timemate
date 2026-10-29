//  Created by homielab.com

import Foundation

/// Whether sleep or a locked screen pauses the timer. "Pause on sleep" stops
/// only a running focus session, so a break keeps running while the Mac sleeps
/// or is locked and simply continues when it wakes or unlocks.
enum SleepPausePolicy {
  static func shouldPause(state: PomodoroState, isBreak: Bool, pauseOnSleep: Bool) -> Bool {
    pauseOnSleep && state == .active && !isBreak
  }

  /// Whether a paused session continues by itself when the user is back: only
  /// one paused by sleep, the lock or being away (never by the user), with "Resume when I'm
  /// back" on, the screen unlocked and the pause not stale (after a stale pause
  /// Resume starts a new cycle, so the user decides).
  static func shouldResume(
    state: PomodoroState, pausedBySleep: Bool, resumeOnReturn: Bool, isScreenLocked: Bool,
    pauseIsStale: Bool
  ) -> Bool {
    resumeOnReturn && pausedBySleep && state == .paused && !isScreenLocked && !pauseIsStale
  }
}
