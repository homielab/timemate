//  Created by homielab.com

import Foundation
import UserNotifications

extension PomodoroTimer {
  func sendNotification() {
    guard notificationsEnabled else { return }
    postNotification(sessionCompleteRequest())
  }

  /// The "session complete" notification for the current session, shown right
  /// away or, with a `trigger`, scheduled for later.
  func sessionCompleteRequest(trigger: UNNotificationTrigger? = nil) -> UNNotificationRequest {
    // Called before the timer moves on, so work out the session that follows.
    let next = SessionSequence.next(
      after: .init(
        sessionType: currentSessionType, focusSessionsCompleted: focusSessionsCompleted),
      interval: longBreakInterval)
    let completion = SessionSequence.completion(
      of: currentSessionType, keepBreakScreenOpen: keepBreakScreenOpen,
      breakScreenShown: breakScreenCanShow)
    let autoStarted = autoStart.shouldStart(next: next.sessionType) && completion == .advance
    return SessionNotification.request(
      forCompleted: currentSessionType, next: next.sessionType,
      minutes: SessionDuration.sanitized(minutesFor(session: next.sessionType)),
      autoStarted: autoStarted, breakThroughFocus: breakThroughFocus,
      label: sessionLabel(for: currentSessionType),
      identifier: trigger == nil
        ? SessionNotification.sessionCompleteIdentifier
        : SessionNotification.fallbackIdentifier,
      trigger: trigger)
  }

  /// Keeps the scheduled copy of the "session complete" notification in step
  /// with the timer, so a session still ends with a notification when the app
  /// quits, crashes or is late (the Mac slept, App Nap). While a session runs
  /// (not a postponed break) the copy is due `SessionNotification.fallbackDelay`
  /// after its end; otherwise none is pending. Called after every change of
  /// the session (`saveSnapshot`) and of the settings: a new end or a new text
  /// (auto-start switched, the next session's length changed...) schedules it again.
  func syncFallbackNotification() {
    let end = state == .active && !isBreakPostponed && notificationsEnabled ? endDate : nil
    guard let end else {
      if fallbackMayBePending {
        removePendingSessionNotification()
      }
      fallbackMayBePending = false
      scheduledFallback = nil
      return
    }
    let fireDate = end.addingTimeInterval(SessionNotification.fallbackDelay)
    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: max(1, fireDate.timeIntervalSince(now())), repeats: false)
    let request = sessionCompleteRequest(trigger: trigger)
    let fallback = ScheduledFallback(end: end, content: request.content)
    guard fallback != scheduledFallback else { return }
    // The fallback identifier: replaces any copy scheduled earlier, never the banner.
    postNotification(request)
    scheduledFallback = fallback
    fallbackMayBePending = true
  }

  /// The session end the scheduled copy is for; `nil` when none was scheduled.
  var scheduledFallbackEnd: Date? { scheduledFallback?.end }

  /// Whether the scheduled copy for the session ending at `end` has already
  /// shown by `tickTime`, so posting the notification again would show it twice.
  func fallbackNotificationShown(forEnd end: Date, at tickTime: Date) -> Bool {
    scheduledFallbackEnd == end
      && tickTime >= end.addingTimeInterval(SessionNotification.fallbackDelay)
  }

  /// Tells the user once a day per goal when the session that ended at `end` took
  /// the pomodoros of its day up to the daily goal. `pomodorosBefore` counts that
  /// day before the session was recorded. A session from an earlier day only
  /// notifies within `DailyGoal.lateNotificationWindow` of its end (a tick late
  /// past midnight), not the next morning.
  func sendDailyGoalNotificationIfReached(pomodorosBefore: Int, endedAt end: Date) {
    let goal = dailyGoal
    let pomodoros = history.totals(on: end).pomodoros
    guard DailyGoal.justReached(before: pomodorosBefore, after: pomodoros, goal: goal)
    else { return }
    let isToday = history.calendar.isDate(end, inSameDayAs: history.currentDate)
    guard isToday || history.currentDate.timeIntervalSince(end) <= DailyGoal.lateNotificationWindow
    else { return }
    let today = end
    let lastNotified = defaults.object(forKey: SettingsKey.dailyGoalNotifiedAt) as? Date
    let notifiedGoal = defaults.object(forKey: SettingsKey.dailyGoalNotifiedGoal) as? Int
    guard
      !DailyGoal.wasNotified(
        on: lastNotified, goal: goal, notifiedGoal: notifiedGoal, today: today,
        calendar: history.calendar)
    else { return }
    guard notificationsEnabled else { return }
    defaults.set(today, forKey: SettingsKey.dailyGoalNotifiedAt)
    defaults.set(goal, forKey: SettingsKey.dailyGoalNotifiedGoal)
    postNotification(SessionNotification.dailyGoalRequest(goal: goal))
  }

  /// Forgets that today's goal was notified, so reaching it again notifies.
  func clearDailyGoalNotified() {
    defaults.removeObject(forKey: SettingsKey.dailyGoalNotifiedAt)
    defaults.removeObject(forKey: SettingsKey.dailyGoalNotifiedGoal)
  }

  /// Settings → Statistics → Reset: deletes the history; the next pomodoro
  /// that reaches the goal notifies again.
  func resetStatistics() {
    history.reset()
    clearDailyGoalNotified()
  }

  /// Runs a button tapped on the "session complete" notification.
  /// "Start Next" starts the session that follows unless it is already running
  /// (auto-start); "Skip" skips it, unless the break screen's skip delay is not over.
  func handleNotificationAction(_ action: SessionNotificationAction) {
    switch action {
    case .startNext:
      startOrContinue()
    case .skip:
      guard skipLockSeconds == 0 else { return }
      skipSession()
    }
  }
}

/// What the scheduled copy of the "session complete" notification was made
/// from: when it is due and what it says. A copy is scheduled again only when
/// this changes.
struct ScheduledFallback: Equatable {
  let end: Date
  let title: String
  let subtitle: String
  let body: String
  let categoryIdentifier: String
  let interruptionLevel: UNNotificationInterruptionLevel

  init(end: Date, content: UNNotificationContent) {
    self.end = end
    title = content.title
    subtitle = content.subtitle
    body = content.body
    categoryIdentifier = content.categoryIdentifier
    interruptionLevel = content.interruptionLevel
  }
}
