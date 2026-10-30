//  Created by homielab.com

import AppIntents
import Foundation

/// Whether the timer runs, as "Get Timer Status" reports it. A finished break
/// waiting on the break screen is `idle`, with no time left.
enum TimerRunState: String, AppEnum {
  case idle, running, paused

  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Timer State")
  static var caseDisplayRepresentations: [TimerRunState: DisplayRepresentation] = [
    .idle: DisplayRepresentation(title: "Not Started"),
    .running: DisplayRepresentation(title: "Running"),
    .paused: DisplayRepresentation(title: "Paused"),
  ]
}

/// The kind of session, as "Get Timer Status" reports it.
enum TimerSessionKind: String, AppEnum {
  case focus, shortBreak, longBreak

  init(_ type: SessionType) {
    switch type {
    case .focus: self = .focus
    case .shortBreak: self = .shortBreak
    case .longBreak: self = .longBreak
    }
  }

  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Session Type")
  static var caseDisplayRepresentations: [TimerSessionKind: DisplayRepresentation] = [
    .focus: DisplayRepresentation(title: "Focus"),
    .shortBreak: DisplayRepresentation(title: "Short Break"),
    .longBreak: DisplayRepresentation(title: "Long Break"),
  ]
}

/// What "Get Timer Status" returns. Its title is the minutes left, so a
/// shortcut that used the old number result still reads a number.
struct TimerStatusEntity: AppEntity {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Timer Status")
  static var defaultQuery = TimerStatusQuery()

  /// There is one timer, so one status.
  let id = "current"

  @Property(title: "State") var state: TimerRunState
  @Property(title: "Session") var kind: TimerSessionKind
  /// Rounded up, so 0 only means the session is over.
  @Property(title: "Minutes Left") var minutesLeft: Int
  @Property(title: "Seconds Left") var secondsLeft: Int
  /// The focus session's label; empty for a break or no label.
  @Property(title: "Label") var label: String
  /// Which focus session of the cycle this is (or the break follows), from 1.
  @Property(title: "Focus Session in Cycle") var cycleIndex: Int
  /// Focus sessions before the long break ("Cycles" in Settings).
  @Property(title: "Focus Sessions per Cycle") var cyclesTotal: Int
  /// The spoken answer, e.g. "Focus, running, 12 min left".
  let summary: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: LocalizedStringResource(stringLiteral: String(minutesLeft)),
      subtitle: LocalizedStringResource(stringLiteral: summary))
  }

  init(
    state: TimerRunState, kind: TimerSessionKind, secondsLeft: Int, label: String?,
    cycleIndex: Int, cyclesTotal: Int, summary: String
  ) {
    self.summary = summary
    let seconds = max(0, secondsLeft)
    self.state = state
    self.kind = kind
    self.secondsLeft = seconds
    self.minutesLeft = (seconds + 59) / 60
    self.label = label ?? ""
    self.cycleIndex = cycleIndex
    self.cyclesTotal = cyclesTotal
  }
}

/// Looks up the one current timer status.
struct TimerStatusQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [TimerStatusEntity] {
    let status = await MainActor.run { TimerIntentActions.status(.shared) }
    return identifiers.contains(status.id) ? [status] : []
  }

  func suggestedEntities() async throws -> [TimerStatusEntity] {
    [await MainActor.run { TimerIntentActions.status(.shared) }]
  }
}

/// What "Get Today's Progress" returns. Its title is the pomodoros done today,
/// so a shortcut that used the old number result still reads a number.
struct TodayProgressEntity: AppEntity {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Today's Progress")
  static var defaultQuery = TodayProgressQuery()

  /// Progress is always today's.
  let id = "today"

  @Property(title: "Pomodoros") var pomodoros: Int
  @Property(title: "Focus Minutes") var focusMinutes: Int
  /// 0 when no daily goal is set.
  @Property(title: "Daily goal") var goal: Int
  @Property(title: "Goal Reached") var goalReached: Bool
  /// Days in a row that met the goal (0 with no goal).
  @Property(title: "Streak Days") var streakDays: Int
  /// The spoken answer, e.g. "Today: 3 of 8 pomodoros, 75 minutes".
  let summary: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: LocalizedStringResource(stringLiteral: String(pomodoros)),
      subtitle: LocalizedStringResource(stringLiteral: summary))
  }

  init(_ progress: TimerIntentActions.TodayProgress) {
    summary = TimerIntentActions.progressText(progress)
    pomodoros = progress.completed
    focusMinutes = progress.focusMinutes
    goal = progress.goal ?? DailyGoal.off
    goalReached = progress.goalReached
    streakDays = progress.streak
  }
}

/// Looks up today's progress.
struct TodayProgressQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [TodayProgressEntity] {
    let progress = await MainActor.run {
      TodayProgressEntity(TimerIntentActions.todayProgress(.shared))
    }
    return identifiers.contains(progress.id) ? [progress] : []
  }

  func suggestedEntities() async throws -> [TodayProgressEntity] {
    [await MainActor.run { TodayProgressEntity(TimerIntentActions.todayProgress(.shared)) }]
  }
}
