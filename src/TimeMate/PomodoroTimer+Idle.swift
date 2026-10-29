//  Created by homielab.com

import Combine
import CoreGraphics
import Foundation

/// "Auto-pause when I'm away" (`IdlePausePolicy`): a running focus session
/// pauses after the chosen minutes without input and gets the time away back;
/// with "Resume when I'm back" on it continues once the user is back.
extension PomodoroTimer {
  /// The "Auto-pause when I'm away" minutes; `IdlePausePolicy.off` when off.
  var idlePauseMinutes: Int {
    IdlePausePolicy.sanitized(defaults.object(forKey: SettingsKey.idlePauseMinutes) as? Int)
  }

  /// Schedules the next look at the idle time for the current state, or none:
  /// while a focus session runs, at the earliest moment the user can reach the
  /// threshold; while a session paused by sleep, the lock or being away may
  /// resume by itself, every `IdlePausePolicy.returnCheckInterval`.
  func updateIdleWatch() {
    idleWatch = nil
    guard let threshold = IdlePausePolicy.threshold(minutes: idlePauseMinutes) else { return }
    if state == .active, !isBreak {
      let idle = idleSeconds()
      let delay = IdlePausePolicy.nextCheckDelay(
        idleSeconds: idle, threshold: threshold,
        isDisplayKeptAwake: idle >= threshold && isDisplayKeptAwake())
      idleWatch = scheduleIdleCheck(delay) { [weak self] in self?.checkAway() }
    } else if canResumeAfterSleep() {
      idleWatch = scheduleIdleCheck(IdlePausePolicy.returnCheckInterval) { [weak self] in
        self?.checkReturn()
      }
    }
  }

  /// A tick decides (`handleTick` pauses a focus session whose user is away);
  /// then the next look is scheduled.
  func checkAway() {
    guard state == .active else { return }
    handleTick()
    if state == .active {
      updateIdleWatch()
    }
  }

  /// The keyboard, mouse or trackpad was used: continue like after an unlock
  /// (`handleUserReturned`); otherwise look again later.
  func checkReturn() {
    if IdlePausePolicy.userIsBack(idleSeconds: idleSeconds()) {
      idleWatch = nil
      handleUserReturned()
    } else {
      updateIdleWatch()
    }
  }

  /// Seconds since the last keyboard, mouse or trackpad event in this login
  /// session. Needs no Accessibility permission and works in the sandbox.
  static func systemIdleSeconds() -> TimeInterval {
    guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
    return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
  }

  /// Runs `block` once on the main run loop after `delay`; cancelling stops it.
  static func scheduleOnMainRunLoop(
    _ delay: TimeInterval, _ block: @escaping () -> Void
  ) -> AnyCancellable {
    let timer = Timer(fire: Date().addingTimeInterval(delay), interval: 0, repeats: false) { _ in
      block()
    }
    timer.tolerance = 1
    RunLoop.main.add(timer, forMode: .common)
    return AnyCancellable { timer.invalidate() }
  }
}
