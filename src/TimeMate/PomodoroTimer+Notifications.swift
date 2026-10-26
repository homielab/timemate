//  Created by homielab.com

import Foundation

extension PomodoroTimer {
  func sendNotification() {
    guard notificationsEnabled else { return }

    // Called before the timer moves on, so work out the session that follows.
    let next = SessionSequence.next(
      after: .init(
        sessionType: currentSessionType, focusSessionsCompleted: focusSessionsCompleted),
      interval: longBreakInterval)
    let completion = SessionSequence.completion(
      of: currentSessionType, keepBreakScreenOpen: keepBreakScreenOpen)
    let autoStarted = autoStartNextSession && completion == .advance
    postNotification(
      SessionNotification.request(
        forCompleted: currentSessionType, next: next.sessionType,
        minutes: SessionDuration.sanitized(minutesFor(session: next.sessionType)),
        autoStarted: autoStarted, breakThroughFocus: breakThroughFocus))
  }

  /// Tells the user once a day when the session that just ended took today's
  /// pomodoros up to the daily goal.
  func sendDailyGoalNotificationIfReached(pomodorosBefore: Int) {
    let goal = dailyGoal
    let pomodoros = history.todayTotals().pomodoros
    guard DailyGoal.justReached(before: pomodorosBefore, after: pomodoros, goal: goal)
    else { return }
    let today = history.currentDate
    let lastNotified = defaults.object(forKey: SettingsKey.dailyGoalNotifiedAt) as? Date
    guard !DailyGoal.wasNotified(on: lastNotified, today: today, calendar: history.calendar)
    else { return }
    defaults.set(today, forKey: SettingsKey.dailyGoalNotifiedAt)
    guard notificationsEnabled else { return }
    postNotification(SessionNotification.dailyGoalRequest(goal: goal))
  }

  /// Runs a button tapped on the "session complete" notification.
  /// "Start Next" starts the session that follows unless it is already running
  /// (auto-start); "Skip" skips it.
  func handleNotificationAction(_ action: SessionNotificationAction) {
    switch action {
    case .startNext:
      if isWaitingToContinue {
        continueWork()
      } else if state != .active {
        startTimer()
      }
    case .skip:
      skipSession()
    }
  }
}
