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

  /// Stops the timer and starts the current session over, like Reset in the
  /// popover and the menu bar item's menu. Nothing is recorded.
  static func reset(_ timer: PomodoroTimer) {
    timer.stopTimer()
  }

  /// Whole minutes left in the current session, rounded up so "0" only means
  /// the session is over.
  static func minutesRemaining(_ timer: PomodoroTimer) -> Int {
    if timer.isWaitingToContinue { return 0 }
    return (max(0, timer.secondsRemaining) + 59) / 60
  }

  /// What "Get Today's Progress" reports.
  struct TodayProgress: Equatable {
    /// Focus sessions completed today.
    let completed: Int
    /// The daily goal; nil when none is set.
    let goal: Int?
    /// Focus time done today, in whole minutes.
    let focusMinutes: Int
    /// True once a goal is set and `completed` has reached it.
    var goalReached: Bool { goal.map { completed >= $0 } ?? false }
    /// Consecutive days that met the goal (0 with no goal).
    var streak = 0
  }

  /// Today's completed pomodoros and focus minutes from `history`, measured
  /// against `goal` (`DailyGoal.off` or less means no goal).
  static func todayProgress(history: SessionHistory, goal: Int) -> TodayProgress {
    let totals = history.todayTotals()
    return TodayProgress(
      completed: totals.pomodoros, goal: goal > DailyGoal.off ? goal : nil,
      focusMinutes: totals.focusMinutes, streak: history.goalStreak(goal: goal))
  }

  /// Spoken / shown answer of "Get Today's Progress", e.g. "Today: 3 of 8 pomodoros, 75 minutes. Streak: 4 days".
  static func progressText(_ progress: TodayProgress) -> String {
    var text: String
    if let goal = progress.goal {
      text = StatisticsText.spokenToday(
        pomodoros: progress.completed, goal: goal, minutes: progress.focusMinutes)
    } else {
      text = StatisticsText.today(pomodoros: progress.completed, minutes: progress.focusMinutes)
    }
    if progress.streak > 0 { text += ". " + StatisticsText.streak(days: progress.streak) }
    return text
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

struct ResetTimerIntent: AppIntent {
  static var title: LocalizedStringResource = "Reset Timer"
  static var description = IntentDescription(
    "Stops the TimeMate timer and starts the current session over.")

  @MainActor
  func perform() async throws -> some IntentResult {
    TimerIntentActions.reset(.shared)
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

struct GetTodayProgressIntent: AppIntent {
  static var title: LocalizedStringResource = "Get Today's Progress"
  static var description = IntentDescription(
    "Returns the pomodoros completed today and says how that compares with the daily goal.")

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
    let timer = PomodoroTimer.shared
    let progress = TimerIntentActions.todayProgress(history: timer.history, goal: timer.dailyGoal)
    return .result(
      value: progress.completed,
      dialog: IntentDialog(stringLiteral: TimerIntentActions.progressText(progress)))
  }
}

/// The keys of the Siri phrases in `TimeMateShortcuts`, as they are written in
/// `AppShortcuts.strings` (`${applicationName}` is the app name). Keep in step with
/// `appShortcuts`: `LocalizationParityTests` checks the Vietnamese table has each one.
enum TimeMateShortcutPhrases {
  static let keys = [
    "Start ${applicationName}",
    "Start a focus session in ${applicationName}",
    "Pause ${applicationName}",
    "Skip session in ${applicationName}",
    "Reset ${applicationName}",
    "How much time is left in ${applicationName}",
    "${applicationName} status",
    "Today's progress in ${applicationName}",
    "${applicationName} progress today",
  ]
}

struct TimeMateShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartTimerIntent(),
      phrases: ["Start \(.applicationName)", "Start a focus session in \(.applicationName)"])
    AppShortcut(intent: PauseTimerIntent(), phrases: ["Pause \(.applicationName)"])
    AppShortcut(intent: SkipSessionIntent(), phrases: ["Skip session in \(.applicationName)"])
    AppShortcut(intent: ResetTimerIntent(), phrases: ["Reset \(.applicationName)"])
    AppShortcut(
      intent: GetTimerStatusIntent(),
      phrases: ["How much time is left in \(.applicationName)", "\(.applicationName) status"])
    AppShortcut(
      intent: GetTodayProgressIntent(),
      phrases: ["Today's progress in \(.applicationName)", "\(.applicationName) progress today"])
  }
}
