//  Created by homielab.com

import Foundation

extension PomodoroTimer {
  /// The display went to sleep or the screen was locked. Pauses only a running
  /// focus session, and only when `pauseOnSleep` is on; it stays paused until
  /// the user resumes it. A break keeps running (see `SleepPausePolicy`).
  func handleScreenInactive() {
    guard
      SleepPausePolicy.shouldPause(
        state: state, isBreak: isBreak,
        pauseOnSleep: defaults.bool(forKey: SettingsKey.pauseOnSleep)
      )
    else { return }
    pauseTimer()
  }

  /// Posted by the system to the distributed center when the screen locks.
  static let screenLockedNotificationName = "com.apple.screenIsLocked"
}
