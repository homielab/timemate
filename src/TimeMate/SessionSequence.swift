//  Created by homielab.com

import Foundation

/// The pure rules behind `PomodoroTimer`: which session follows, what happens
/// when one ends, and what "+5 min" and "Postpone" do to a break. Nothing here
/// touches timers, defaults or the clock, so each rule can be tested directly.
enum SessionSequence {
  /// Where the timer stands in the focus/break cycle.
  struct Position: Equatable {
    var sessionType: SessionType
    /// Focus sessions finished since the last long break.
    var focusSessionsCompleted: Int
  }

  /// The session after `position`. Finishing (or skipping) a focus session
  /// counts it; the `interval`-th one leads to a long break and restarts the
  /// count. Any break leads back to focus.
  static func next(after position: Position, interval: Int) -> Position {
    guard position.sessionType == .focus else {
      return Position(sessionType: .focus, focusSessionsCompleted: position.focusSessionsCompleted)
    }
    let completed = position.focusSessionsCompleted + 1
    if completed >= interval {
      return Position(sessionType: .longBreak, focusSessionsCompleted: 0)
    }
    return Position(sessionType: .shortBreak, focusSessionsCompleted: completed)
  }

  static func isBreak(_ type: SessionType) -> Bool {
    type == .shortBreak || type == .longBreak
  }

  /// What the timer does when a session runs to its end.
  enum Completion: Equatable {
    /// The break screen stays up until the user continues.
    case waitOnBreakScreen
    /// The next session follows (and starts if auto-start is on).
    case advance
  }

  static func completion(of type: SessionType, keepBreakScreenOpen: Bool) -> Completion {
    keepBreakScreenOpen && isBreak(type) ? .waitOnBreakScreen : .advance
  }

  // MARK: - Extending and postponing a break

  /// The countdown a break ends up with after "+N min" or "Postpone".
  struct Adjustment: Equatable {
    var state: PomodoroState
    var totalDuration: Int
    var timeRemaining: Int
    /// `nil` while paused.
    var endDate: Date?
    var progress: Double

    init(state: PomodoroState, totalDuration: Int, timeRemaining: Int, endDate: Date?) {
      self.state = state
      self.totalDuration = totalDuration
      self.timeRemaining = timeRemaining
      self.endDate = endDate
      self.progress = Double(timeRemaining) / Double(max(1, totalDuration))
    }
  }

  /// The timer's countdown as `extend` and `postpone` read it.
  struct Countdown: Equatable {
    var sessionType: SessionType
    var state: PomodoroState
    var totalDuration: Int
    var timeRemaining: Int
    var endDate: Date?
    var isBreakPostponed: Bool
    var isWaitingToContinue: Bool
  }

  /// Whether the popover offers "+5 min" for this session: a focus session that is
  /// running or paused (a break is extended from its break screen).
  static func offersFocusExtend(sessionType: SessionType, state: PomodoroState) -> Bool {
    sessionType == .focus && state != .idle
  }

  /// Adds `extra` seconds to the running session. A break that already ended and
  /// waits on the break screen starts again for `extra`. `nil` means nothing
  /// changes (idle, a postponed break, or nothing to add).
  static func extend(_ countdown: Countdown, by extra: Int, now: Date) -> Adjustment? {
    guard extra > 0, !countdown.isBreakPostponed else { return nil }
    if countdown.isWaitingToContinue {
      guard isBreak(countdown.sessionType) else { return nil }
      return Adjustment(
        state: .active, totalDuration: extra, timeRemaining: extra,
        endDate: now.addingTimeInterval(TimeInterval(extra)))
    }
    switch countdown.state {
    case .active:
      guard let endDate = countdown.endDate else { return nil }
      let newEndDate = endDate.addingTimeInterval(TimeInterval(extra))
      return Adjustment(
        state: .active, totalDuration: countdown.totalDuration + extra,
        timeRemaining: max(0, Int(newEndDate.timeIntervalSince(now).rounded())),
        endDate: newEndDate)
    case .paused:
      return Adjustment(
        state: .paused, totalDuration: countdown.totalDuration + extra,
        timeRemaining: countdown.timeRemaining + extra, endDate: nil)
    case .idle:
      return nil
    }
  }

  /// Puts the running break off for `delay` seconds; the caller marks it
  /// postponed. `nil` unless a break is actively running and not postponed.
  static func postpone(_ countdown: Countdown, delay: Int, now: Date) -> Adjustment? {
    guard delay > 0, isBreak(countdown.sessionType), countdown.state == .active,
      !countdown.isBreakPostponed
    else { return nil }
    return Adjustment(
      state: .active, totalDuration: delay, timeRemaining: delay,
      endDate: now.addingTimeInterval(TimeInterval(delay)))
  }
}

enum SessionType: String, CaseIterable, Codable {
  case focus = "Focus"
  case shortBreak = "Short Break"
  case longBreak = "Long Break"
}

enum PomodoroState: String, Codable {
  case idle, active, paused
}
