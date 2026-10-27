//  Created by homielab.com

import Foundation

/// What `PomodoroTimer` does with the snapshot saved before the app quit.
/// The decision is pure: `now` and the settings come in as arguments.
enum TimerRestorePlan: Equatable {
  /// Nothing to resume: the timer waits, idle, on the saved session.
  case idle
  /// A break screen was waiting for the user: wait on the next session instead.
  case advanceFromWaitingBreak
  /// A paused session stays paused.
  case paused(remaining: Int, totalDuration: Int, isBreakPostponed: Bool)
  /// A running session (or postponed break) that is still due keeps counting
  /// to `endDate`, which is never later than `now` + the session length.
  case resume(endDate: Date, remaining: Int, totalDuration: Int, isBreakPostponed: Bool)
  /// A postponed break came due while the app was closed; it waits at full
  /// length for Start.
  case postponedBreakDue
  /// The session ended while the app was closed: record it as ended at
  /// `endDate`, then move on to the next session (started if `startNext`).
  case expired(endDate: Date, duration: Int, startNext: Bool)

  /// A session that ended more than `overdueGracePeriod` before `now` never
  /// starts the next one: the user comes back to a waiting timer.
  static func make(
    from snapshot: TimerSnapshot, now: Date, autoStart: AutoStart,
    keepBreakScreenOpen: Bool, breakScreenShown: Bool, overdueGracePeriod: TimeInterval
  ) -> TimerRestorePlan {
    switch snapshot.state {
    case .idle:
      return snapshot.isWaitingToContinue ? .advanceFromWaitingBreak : .idle
    case .paused:
      return .paused(
        remaining: min(snapshot.remaining, snapshot.totalDuration),
        totalDuration: snapshot.totalDuration, isBreakPostponed: snapshot.isBreakPostponed)
    case .active:
      guard let savedEndDate = snapshot.endDate else { return .idle }
      if savedEndDate > now {
        // A clock set back while the app was closed cannot stretch the session.
        let latestEnd = now.addingTimeInterval(TimeInterval(snapshot.totalDuration))
        let endDate = min(savedEndDate, latestEnd)
        return .resume(
          endDate: endDate,
          remaining: max(0, Int(endDate.timeIntervalSince(now).rounded())),
          totalDuration: snapshot.totalDuration, isBreakPostponed: snapshot.isBreakPostponed)
      }
      if snapshot.isBreakPostponed { return .postponedBreakDue }
      let waitsOnBreakScreen =
        SessionSequence.completion(
          of: snapshot.sessionType, keepBreakScreenOpen: keepBreakScreenOpen,
          breakScreenShown: breakScreenShown)
        == .waitOnBreakScreen
      // Any break is followed by focus; focus by a short or long break.
      let nextType: SessionType =
        SessionSequence.isBreak(snapshot.sessionType) ? .focus : .shortBreak
      return .expired(
        endDate: savedEndDate, duration: snapshot.totalDuration,
        startNext: autoStart.shouldStart(next: nextType) && !waitsOnBreakScreen
          && now.timeIntervalSince(savedEndDate) <= overdueGracePeriod)
    }
  }
}
