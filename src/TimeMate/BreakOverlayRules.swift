//  Created by homielab.com

import Foundation

/// When the full-screen break overlay is shown, and what a double Esc on it does.
enum BreakOverlayRules {
  /// What a double press of Esc on the overlay does.
  enum EscAction: Equatable {
    /// The break has ended and waits for the user: start the next focus session.
    case continueWork
    /// The break is still running: end it early.
    case skipSession
  }

  /// The overlay shows during a running, not postponed break, and on the "break is
  /// over" screen, but only while the user has it turned on.
  static func shouldShowOverlay(
    state: PomodoroState, sessionType: SessionType, isWaiting: Bool, isPostponed: Bool,
    enabled: Bool
  ) -> Bool {
    guard enabled else { return false }
    let isBreak = sessionType == .shortBreak || sessionType == .longBreak
    return (state == .active && isBreak && !isPostponed) || isWaiting
  }

  static func escAction(isWaitingToContinue: Bool) -> EscAction {
    isWaitingToContinue ? .continueWork : .skipSession
  }
}

/// Recognizes two presses of Esc in quick succession. A single press does
/// nothing, so a stray Esc can't end a break.
struct DoubleEscDetector {
  static let escKeyCode: UInt16 = 53
  /// The longest gap between the two presses.
  static let defaultInterval: TimeInterval = 0.5

  private let interval: TimeInterval
  private let now: () -> Date
  private var lastPress: Date?

  init(interval: TimeInterval = defaultInterval, now: @escaping () -> Date = Date.init) {
    self.interval = interval
    self.now = now
  }

  /// Records a press of Esc and returns whether it completes a double press.
  /// After a double press the next press starts over.
  mutating func registerPress() -> Bool {
    let time = now()
    if let lastPress, time.timeIntervalSince(lastPress) < interval {
      self.lastPress = nil
      return true
    }
    lastPress = time
    return false
  }
}
