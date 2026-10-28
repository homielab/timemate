//  Created by homielab.com

import Foundation

/// Whether sleep or a locked screen pauses the timer. "Pause on sleep" stops
/// only a running focus session, so a break keeps running while the Mac sleeps
/// or is locked and simply continues when it wakes or unlocks.
enum SleepPausePolicy {
  static func shouldPause(state: PomodoroState, isBreak: Bool, pauseOnSleep: Bool) -> Bool {
    pauseOnSleep && state == .active && !isBreak
  }
}
