//  Created by homielab.com

import AppIntents
import Foundation

/// What the Shortcuts actions do to the timer. Kept apart from the `AppIntent`
/// types so tests can run it against their own `PomodoroTimer`.
enum TimerIntentActions {
  /// Starts or resumes the current session; past a finished break that waits
  /// on the break screen, continues with the next session. A running timer is
  /// left alone, so running the shortcut twice never pauses it.
  static func start(_ timer: PomodoroTimer) {
    if timer.isWaitingToContinue {
      timer.continueWork()
    } else if timer.state != .active {
      timer.startTimer()
    }
  }

  /// Pauses a running timer; does nothing otherwise.
  static func pause(_ timer: PomodoroTimer) {
    timer.pauseTimer()
  }

  /// Ends the current session and moves to the next one.
  static func skip(_ timer: PomodoroTimer) {
    timer.skipSession()
  }

  /// Whole minutes left in the current session, rounded up so "0" only means
  /// the session is over.
  static func minutesRemaining(_ timer: PomodoroTimer) -> Int {
    if timer.isWaitingToContinue { return 0 }
    return (max(0, timer.secondsRemaining) + 59) / 60
  }

  /// Spoken / shown answer of "Get Timer Status", e.g. "Focus, running, 12 min left".
  static func statusText(_ timer: PomodoroTimer) -> String {
    let session = NSLocalizedString(
      timer.isBreakPostponed ? "Break postponed" : timer.currentSessionType.rawValue,
      comment: "")
    if timer.isWaitingToContinue {
      return String(format: NSLocalizedString("%@ finished", comment: "Shortcuts status"), session)
    }
    let format: String
    switch timer.state {
    case .active: format = NSLocalizedString("%1$@, running, %2$d min left", comment: "Shortcuts")
    case .paused: format = NSLocalizedString("%1$@, paused, %2$d min left", comment: "Shortcuts")
    case .idle: format = NSLocalizedString("%1$@, not started, %2$d min", comment: "Shortcuts")
    }
    return String(format: format, session, minutesRemaining(timer))
  }
}

struct StartTimerIntent: AppIntent {
  static var title: LocalizedStringResource = "Start Timer"
  static var description = IntentDescription(
    "Starts or resumes the current TimeMate session.")

  @MainActor
  func perform() async throws -> some IntentResult {
    TimerIntentActions.start(.shared)
    return .result()
  }
}

struct PauseTimerIntent: AppIntent {
  static var title: LocalizedStringResource = "Pause Timer"
  static var description = IntentDescription("Pauses the running TimeMate session.")

  @MainActor
  func perform() async throws -> some IntentResult {
    TimerIntentActions.pause(.shared)
    return .result()
  }
}

struct SkipSessionIntent: AppIntent {
  static var title: LocalizedStringResource = "Skip Session"
  static var description = IntentDescription(
    "Ends the current TimeMate session and moves to the next one.")

  @MainActor
  func perform() async throws -> some IntentResult {
    TimerIntentActions.skip(.shared)
    return .result()
  }
}

struct GetTimerStatusIntent: AppIntent {
  static var title: LocalizedStringResource = "Get Timer Status"
  static var description = IntentDescription(
    "Returns the minutes left in the current TimeMate session and says which session it is.")

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
    let timer = PomodoroTimer.shared
    return .result(
      value: TimerIntentActions.minutesRemaining(timer),
      dialog: IntentDialog(stringLiteral: TimerIntentActions.statusText(timer)))
  }
}

struct TimeMateShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartTimerIntent(),
      phrases: ["Start \(.applicationName)", "Start a focus session in \(.applicationName)"])
    AppShortcut(intent: PauseTimerIntent(), phrases: ["Pause \(.applicationName)"])
    AppShortcut(intent: SkipSessionIntent(), phrases: ["Skip session in \(.applicationName)"])
    AppShortcut(
      intent: GetTimerStatusIntent(),
      phrases: ["How much time is left in \(.applicationName)", "\(.applicationName) status"])
  }
}
