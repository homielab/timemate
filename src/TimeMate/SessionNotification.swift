//  Created by homielab.com

import Foundation
import UserNotifications
import os

/// Buttons on the "session complete" notification.
enum SessionNotificationAction: String, CaseIterable {
  case startNext = "com.homielab.timemate.action.startNext"
  case skip = "com.homielab.timemate.action.skip"

  /// Untranslated title, looked up in `Localizable.strings`.
  var titleKey: String {
    switch self {
    case .startNext: return "Start Next"
    case .skip: return "Skip"
    }
  }
}

/// What the app does when the user answers one of its notifications.
enum NotificationResponse: Equatable {
  /// A button on the "session complete" notification.
  case timerAction(SessionNotificationAction)
  /// The body of the banner was clicked: show the timer.
  case openPopover
  /// Dismissed, or an action the app doesn't know.
  case ignore

  init(actionIdentifier: String) {
    if let action = SessionNotificationAction(rawValue: actionIdentifier) {
      self = .timerAction(action)
    } else if actionIdentifier == UNNotificationDefaultActionIdentifier {
      self = .openPopover
    } else {
      self = .ignore
    }
  }
}

/// Builds the "session complete" notification and its category.
enum SessionNotification {
  static let categoryIdentifier = "com.homielab.timemate.category.sessionComplete"
  /// Same notification when the next session has already started: only "Skip".
  static let autoStartedCategoryIdentifier =
    "com.homielab.timemate.category.sessionCompleteAutoStarted"
  /// Category of a break that ended with focus waiting: only "Start Next",
  /// because "Skip" would skip the focus session that has not started yet.
  static let breakEndedCategoryIdentifier = "com.homielab.timemate.category.breakEnded"
  /// Groups all TimeMate session notifications into one stack in Notification Center.
  static let threadIdentifier = "com.homielab.timemate.sessions"

  /// Registers categories and requests notification authorization.
  static func configure(delegate: UNUserNotificationCenterDelegate) {
    let center = UNUserNotificationCenter.current()
    center.delegate = delegate
    center.setNotificationCategories(categories())
    center.requestAuthorization(options: [.alert, .badge, .sound]) { _, error in
      if let error {
        os.Logger.app.error("Notification authorization failed: \(error.localizedDescription)")
      }
    }
  }

  /// The category with the "Start Next" and "Skip" buttons.
  static func category() -> UNNotificationCategory {
    category(identifier: categoryIdentifier, actions: SessionNotificationAction.allCases)
  }

  /// The category for a next session that started by itself: "Start Next" would do nothing.
  static func autoStartedCategory() -> UNNotificationCategory {
    category(identifier: autoStartedCategoryIdentifier, actions: [.skip])
  }

  /// The category for a finished break whose focus session waits to be started.
  static func breakEndedCategory() -> UNNotificationCategory {
    category(identifier: breakEndedCategoryIdentifier, actions: [.startNext])
  }

  /// All categories; register them at launch.
  static func categories() -> Set<UNNotificationCategory> {
    [category(), autoStartedCategory(), breakEndedCategory()]
  }

  /// Category for the end of `completed`: auto-started → only "Skip"; a break
  /// ending with focus waiting → only "Start Next"; otherwise both.
  static func categoryIdentifier(completed: SessionType, autoStarted: Bool) -> String {
    if autoStarted { return autoStartedCategoryIdentifier }
    return completed == .focus ? categoryIdentifier : breakEndedCategoryIdentifier
  }

  private static func category(
    identifier: String, actions: [SessionNotificationAction]
  ) -> UNNotificationCategory {
    let buttons = actions.map { action in
      UNNotificationAction(
        identifier: action.rawValue,
        title: NSLocalizedString(action.titleKey, comment: "Notification action button"),
        options: [])
    }
    return UNNotificationCategory(
      identifier: identifier, actions: buttons, intentIdentifiers: [], options: [])
  }

  /// "Next: Short Break · 5 min", or "Short Break started · 5 min" when it already runs.
  static func body(next: SessionType, minutes: Int, autoStarted: Bool) -> String {
    let session = NSLocalizedString(next.rawValue, comment: "The name of the next session type")
    let length = String(format: NSLocalizedString("%lld min", comment: "Minutes"), minutes)
    let format =
      autoStarted
      ? NSLocalizedString("%1$@ started · %2$@", comment: "Notification body, next session runs")
      : NSLocalizedString("Next: %1$@ · %2$@", comment: "Notification body, next session waits")
    return String(format: format, session, length)
  }

  /// Content for the end of a session of `sessionType`. It carries no sound: the
  /// app already plays the alarm chosen in Settings, so the user hears it once.
  ///
  /// With `breakThroughFocus` the notification is time-sensitive, so a Focus
  /// mode (or Do Not Disturb) still shows it unless the user turned that off
  /// for TimeMate in System Settings. A focus session's `label` is the first
  /// line of the body.
  static func content(
    forCompleted sessionType: SessionType, next: SessionType, minutes: Int,
    autoStarted: Bool, breakThroughFocus: Bool = true, label: String? = nil
  ) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = "TimeMate"
    let localizedSessionTitle = NSLocalizedString(
      sessionType.rawValue, comment: "The name of the current session type")
    content.subtitle = String(
      format: NSLocalizedString("%@ session complete!", comment: "Notification format string"),
      localizedSessionTitle
    )
    let nextLine = body(next: next, minutes: minutes, autoStarted: autoStarted)
    if let label = SessionLabel.normalized(label) {
      content.body = label + "\n" + nextLine
    } else {
      content.body = nextLine
    }
    content.sound = nil
    content.categoryIdentifier = categoryIdentifier(
      completed: sessionType, autoStarted: autoStarted)
    content.threadIdentifier = threadIdentifier
    content.interruptionLevel = breakThroughFocus ? .timeSensitive : .active
    return content
  }

  /// Identifier of the "daily goal reached" notification; a new one replaces the old.
  static let dailyGoalIdentifier = "com.homielab.timemate.dailyGoalReached"

  /// "Daily goal reached: 8 pomodoros today." It has no buttons and no sound
  /// (the session-complete alarm has just played) and is not time-sensitive.
  static func dailyGoalContent(goal: Int, bundle: Bundle = .main)
    -> UNMutableNotificationContent
  {
    let content = UNMutableNotificationContent()
    content.title = "TimeMate"
    content.subtitle = StatisticsText.goalReached(goal: goal, bundle: bundle)
    content.sound = nil
    content.threadIdentifier = threadIdentifier
    content.interruptionLevel = .active
    return content
  }

  static func dailyGoalRequest(goal: Int) -> UNNotificationRequest {
    UNNotificationRequest(
      identifier: dailyGoalIdentifier, content: dailyGoalContent(goal: goal), trigger: nil)
  }

  /// Identifier of every "session complete" notification: a new one replaces
  /// the previous, so Notification Center never holds buttons for an older session.
  static let sessionCompleteIdentifier = "com.homielab.timemate.sessionComplete"

  /// Removes the "session complete" notification from Notification Center
  /// (the user has moved on), leaving the daily goal one and other apps' alone.
  static func removeDelivered() {
    let center = UNUserNotificationCenter.current()
    center.removeDeliveredNotifications(withIdentifiers: [sessionCompleteIdentifier])
    center.removePendingNotificationRequests(withIdentifiers: [sessionCompleteIdentifier])
  }

  /// How long after a session's end its scheduled copy of the notification
  /// fires. The app posts the notification itself as the session ends, under
  /// the same identifier, which replaces the scheduled copy; so the copy only
  /// shows when the app is not running or is late (the Mac slept, App Nap).
  static let fallbackDelay: TimeInterval = 3

  /// Cancels the scheduled copy of the "session complete" notification; one
  /// already shown stays in Notification Center.
  static func removePending() {
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: [sessionCompleteIdentifier])
  }

  /// Hands `request` to Notification Center; a failure (notifications denied,
  /// a bad trigger) is logged so a missing banner can be traced in Console.app.
  static func post(
    _ request: UNNotificationRequest, center: UNUserNotificationCenter = .current()
  ) {
    center.add(request) { error in
      if let error { logPostFailure(error, identifier: request.identifier) }
    }
  }

  /// Logs a notification that could not be posted.
  static func logPostFailure(_ error: Error, identifier: String) {
    let reason = error.localizedDescription
    os.Logger.app.error(
      "Notification \(identifier, privacy: .public) not posted: \(reason, privacy: .public)")
  }

  /// The request that shows the notification right away, or at `trigger`.
  static func request(
    forCompleted sessionType: SessionType, next: SessionType, minutes: Int,
    autoStarted: Bool, breakThroughFocus: Bool, label: String? = nil,
    identifier: String = sessionCompleteIdentifier, trigger: UNNotificationTrigger? = nil
  ) -> UNNotificationRequest {
    UNNotificationRequest(
      identifier: identifier,
      content: content(
        forCompleted: sessionType, next: next, minutes: minutes, autoStarted: autoStarted,
        breakThroughFocus: breakThroughFocus, label: label),
      trigger: trigger)
  }
}
