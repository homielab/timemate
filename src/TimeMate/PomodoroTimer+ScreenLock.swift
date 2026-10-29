//  Created by homielab.com

import Foundation

extension PomodoroTimer {
  /// How long after the user is back (unlock, display or Mac wake) a session
  /// paused by sleep or the lock waits before it continues.
  static let resumeDelay: TimeInterval = 2

  /// The display went to sleep or the screen was locked. Pauses only a running
  /// focus session, and only when `pauseOnSleep` is on; it stays paused until
  /// the user resumes it, or until they are back with `resumeOnReturn` on.
  /// A break keeps running (see `SleepPausePolicy`).
  func handleScreenInactive() {
    guard
      SleepPausePolicy.shouldPause(
        state: state, isBreak: isBreak,
        pauseOnSleep: defaults.bool(forKey: SettingsKey.pauseOnSleep)
      )
    else { return }
    pauseForSleep()
  }

  /// Pauses the running session and marks the pause as the system's, so it
  /// may resume by itself; a pause by the user never does.
  func pauseForSleep() {
    pauseTimer()
    if state == .paused {
      pausedBySleep = true
    }
  }

  /// The screen was unlocked, or the display or the Mac woke up. With
  /// `resumeOnReturn` on, a session paused by sleep or the lock continues
  /// `resumeDelay` later, if the screen is still unlocked then. A pause older
  /// than `SessionCycle.isStale` allows stays: Resume then starts a new cycle.
  func handleUserReturned() {
    guard canResumeAfterSleep() else { return }
    scheduleResume(Self.resumeDelay) { [weak self] in
      guard let self, self.canResumeAfterSleep() else { return }
      self.startTimer()
    }
  }

  /// Whether a session paused by sleep, the lock or being away would continue
  /// now that the user is back (`SleepPausePolicy.shouldResume`).
  func canResumeAfterSleep() -> Bool {
    SleepPausePolicy.shouldResume(
      state: state, pausedBySleep: pausedBySleep,
      resumeOnReturn: defaults.bool(forKey: SettingsKey.resumeOnReturn),
      isScreenLocked: isScreenLocked,
      pauseIsStale: SessionCycle.pauseRestartsCycle(
        pausedAt: pausedAt, now: now(), calendar: history.calendar))
  }

  /// Posted by the system to the distributed center when the screen locks.
  static let screenLockedNotificationName = "com.apple.screenIsLocked"
  /// Posted by the system to the distributed center when the screen unlocks.
  static let screenUnlockedNotificationName = "com.apple.screenIsUnlocked"
}
