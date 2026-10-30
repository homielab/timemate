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
    timer.startOrContinue()
  }

  /// Sets what the next focus session is about, then starts like `start`,
  /// except that an idle timer sitting on a break starts focus instead of the
  /// break. The label goes into the popover's "What are you working on?" field
  /// only when a new session begins (idle, or past a finished break); a running
  /// or paused session keeps the label it began with. A blank or missing label
  /// leaves the field as it is.
  static func startFocus(_ timer: PomodoroTimer, label: String? = nil) {
    let beginsNewSession = timer.isWaitingToContinue || timer.state == .idle
    if beginsNewSession, let label = SessionLabel.normalized(label) {
      timer.defaults.set(label, forKey: SettingsKey.sessionLabel)
    }
    timer.startFocus()
  }

  /// Shortest and longest extension "Add Time" accepts, in minutes.
  static let extendRange = 1...60

  /// Outcome of "Add Time".
  enum ExtendResult: Equatable {
    case added(Int)
    case atLimit
    case noSession

    /// The value "Add Time" returns to Shortcuts: minutes added, 0 when none.
    var minutesAdded: Int {
      if case .added(let minutes) = self { return minutes }
      return 0
    }
  }

  /// Adds `minutes` (kept within `extendRange`) to a running or paused session,
  /// or restarts a finished break waiting on the break screen for that long,
  /// like "+5 min". The session stops at the 180-minute limit, so fewer minutes
  /// may be added. Does nothing when idle or during a postponed break.
  @discardableResult
  static func extend(_ timer: PomodoroTimer, minutes: Int) -> ExtendResult {
    let clamped = min(max(minutes, extendRange.lowerBound), extendRange.upperBound)
    if timer.isAtSessionLimit { return .atLimit }
    let wasWaiting = timer.isWaitingToContinue
    let before = wasWaiting ? 0 : timer.sessionLengthSeconds
    guard timer.extend(by: clamped) else { return .noSession }
    let addedSeconds = timer.sessionLengthSeconds - before
    let perMinute = PomodoroTimer.seconds(forMinutes: 1)
    return .added((addedSeconds + perMinute - 1) / perMinute)
  }

  /// Spoken / shown answer of "Add Time": "Added 5 minutes", "Already at the
  /// 180-minute limit", or "No session to extend" (idle, or a postponed break).
  static func extendText(_ result: ExtendResult) -> String {
    let added: Int
    switch result {
    case .noSession:
      return NSLocalizedString("No session to extend", comment: "Shortcuts Add Time result")
    case .atLimit:
      return String(
        format: NSLocalizedString(
          "Already at the %d-minute limit", comment: "Shortcuts Add Time result"),
        SessionDuration.minuteRange.upperBound)
    case .added(let minutes):
      added = minutes
    }
    if added == 1 {
      return NSLocalizedString("Added 1 minute", comment: "Shortcuts Add Time result")
    }
    return String(
      format: NSLocalizedString("Added %d minutes", comment: "Shortcuts Add Time result"), added)
  }

  /// Pauses a running timer; does nothing otherwise. Throws while the break
  /// screen's skip delay is not over.
  static func pause(_ timer: PomodoroTimer) throws {
    if timer.state == .active { try checkSkipLock(timer) }
    timer.pauseTimer()
  }

  /// Ends the current session and moves to the next one. Throws while the break
  /// screen's skip delay is not over.
  static func skip(_ timer: PomodoroTimer) throws {
    try checkSkipLock(timer)
    timer.skipSession()
  }

  private static func checkSkipLock(_ timer: PomodoroTimer) throws {
    if timer.skipLockSeconds > 0 { throw SkipLockedError(message: timer.skipLockText) }
  }

  /// Stops the timer and starts the current session over, like Reset in the
  /// popover and the menu bar item's menu. A focus session past half is recorded
  /// first, without asking; returns "Recorded N min of focus" then, else nil.
  /// Throws while the break screen's skip delay is not over.
  @discardableResult
  static func reset(_ timer: PomodoroTimer) throws -> String? {
    try checkSkipLock(timer)
    return recordedText(seconds: timer.stopTimer(recording: true))
  }

  /// "Recorded N min of focus" for a reset that saved at least a whole minute.
  static func recordedText(seconds: TimeInterval) -> String? {
    let minutes = Int(seconds / 60)
    guard minutes >= 1 else { return nil }
    return String(format: NSLocalizedString("Recorded %d min of focus", comment: ""), minutes)
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
  static func todayProgress(
    history: SessionHistory, goal: Int, skipWeekends: Bool = false
  ) -> TodayProgress {
    let totals = history.todayTotals()
    return TodayProgress(
      completed: totals.pomodoros, goal: goal > DailyGoal.off ? goal : nil,
      focusMinutes: totals.focusMinutes,
      streak: history.goalStreak(goal: goal, skipWeekends: skipWeekends))
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

  /// `statusText` as the answer of a command (Start, Pause, Skip, Reset), so
  /// Siri and Shortcuts say where the timer is after it ran.
  static func statusDialog(_ timer: PomodoroTimer) -> IntentDialog {
    IntentDialog(stringLiteral: statusText(timer))
  }
}

struct StartTimerIntent: AppIntent {
  static var title: LocalizedStringResource = "Start Timer"
  static var description = IntentDescription(
    "Starts or resumes the current TimeMate session.")

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    TimerIntentActions.start(.shared)
    return .result(dialog: TimerIntentActions.statusDialog(.shared))
  }
}

struct StartFocusSessionIntent: AppIntent {
  static var title: LocalizedStringResource = "Start Focus"
  static var description = IntentDescription(
    "Starts a TimeMate focus session, or resumes the current session. A break that has not started yet is skipped."
  )

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    TimerIntentActions.startFocus(.shared)
    return .result(dialog: TimerIntentActions.statusDialog(.shared))
  }
}

struct StartFocusIntent: AppIntent {
  static var title: LocalizedStringResource = "Start Focus with Label"
  static var description = IntentDescription(
    "Sets what you are working on and starts a TimeMate focus session, or resumes the current session. A running session keeps its label."
  )

  @Parameter(title: "Label", requestValueDialog: "What are you working on?")
  var label: String

  static var parameterSummary: some ParameterSummary {
    Summary("Start focus on \(\.$label)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    TimerIntentActions.startFocus(.shared, label: label)
    return .result(dialog: TimerIntentActions.statusDialog(.shared))
  }
}

struct ExtendSessionIntent: AppIntent {
  static var title: LocalizedStringResource = "Add Time"
  static var description = IntentDescription(
    "Adds minutes (1 to 60) to the running or paused TimeMate session, or restarts a finished break for that long."
  )

  @Parameter(title: "Minutes", default: 5, inclusiveRange: (1, 60))
  var minutes: Int

  /// Shortcuts reads the summary with the chosen value, so 1 gets the singular noun.
  static var parameterSummary: some ParameterSummary {
    When(\.$minutes, .equalTo, 1) {
      Summary("Add \(\.$minutes) minute")
    } otherwise: {
      Summary("Add \(\.$minutes) minutes")
    }
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
    let added = TimerIntentActions.extend(.shared, minutes: minutes)
    return .result(
      value: added.minutesAdded,
      dialog: IntentDialog(stringLiteral: TimerIntentActions.extendText(added)))
  }
}

/// Skip or pause asked while the break screen's skip delay is not over.
struct SkipLockedError: Error, CustomLocalizedStringResourceConvertible, Equatable {
  let message: String
  var localizedStringResource: LocalizedStringResource { "\(message)" }
}

struct PauseTimerIntent: AppIntent {
  static var title: LocalizedStringResource = "Pause Timer"
  static var description = IntentDescription("Pauses the running TimeMate session.")

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    try TimerIntentActions.pause(.shared)
    return .result(dialog: TimerIntentActions.statusDialog(.shared))
  }
}

struct SkipSessionIntent: AppIntent {
  static var title: LocalizedStringResource = "Skip Session"
  static var description = IntentDescription(
    "Ends the current TimeMate session and moves to the next one.")

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    try TimerIntentActions.skip(.shared)
    return .result(dialog: TimerIntentActions.statusDialog(.shared))
  }
}

struct ResetTimerIntent: AppIntent {
  static var title: LocalizedStringResource = "Reset Timer"
  static var description = IntentDescription(
    "Stops the TimeMate timer and starts the current session over. Focus time so far is saved."
  )

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let recorded = try TimerIntentActions.reset(.shared)
    let status = TimerIntentActions.statusText(.shared)
    return .result(
      dialog: IntentDialog(stringLiteral: recorded.map { "\($0). \(status)" } ?? status))
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
      dialog: TimerIntentActions.statusDialog(timer))
  }
}

struct GetTodayProgressIntent: AppIntent {
  static var title: LocalizedStringResource = "Get Today's Progress"
  static var description = IntentDescription(
    "Returns the pomodoros completed today and says how that compares with the daily goal.")

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
    let timer = PomodoroTimer.shared
    let progress = TimerIntentActions.todayProgress(
      history: timer.history, goal: timer.dailyGoal, skipWeekends: timer.streakSkipsWeekends)
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
    "Start focus with a label in ${applicationName}",
    "Add time in ${applicationName}",
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
      intent: StartTimerIntent(), phrases: ["Start \(.applicationName)"])
    AppShortcut(
      intent: StartFocusSessionIntent(),
      phrases: ["Start a focus session in \(.applicationName)"])
    AppShortcut(
      intent: StartFocusIntent(),
      phrases: ["Start focus with a label in \(.applicationName)"])
    AppShortcut(intent: ExtendSessionIntent(), phrases: ["Add time in \(.applicationName)"])
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
