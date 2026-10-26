//  Created by homielab.com

import Foundation

extension PomodoroTimer {
  /// The display went to sleep or the screen was locked. Only acts when
  /// `pauseOnSleep` is on; the session stays paused until the user resumes it.
  func handleScreenInactive() {
    guard defaults.bool(forKey: SettingsKey.pauseOnSleep) else { return }
    pauseTimer()
  }

  /// Posted by the system to the distributed center when the screen locks.
  static let screenLockedNotificationName = "com.apple.screenIsLocked"
}
