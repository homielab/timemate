//  Created by homielab.com

import Foundation
import UserNotifications

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
  /// Groups all TimeMate session notifications into one stack in Notification Center.
  static let threadIdentifier = "com.homielab.timemate.sessions"

  /// The category with the "Start Next" and "Skip" buttons; register it at launch.
  static func category() -> UNNotificationCategory {
    let actions = SessionNotificationAction.allCases.map { action in
      UNNotificationAction(
        identifier: action.rawValue,
        title: NSLocalizedString(action.titleKey, comment: "Notification action button"),
        options: [])
    }
    return UNNotificationCategory(
      identifier: categoryIdentifier, actions: actions, intentIdentifiers: [], options: [])
  }

  /// Content for the end of a session of `sessionType`. It carries no sound: the
  /// app already plays the alarm chosen in Settings, so the user hears it once.
  ///
  /// With `breakThroughFocus` the notification is time-sensitive, so a Focus
  /// mode (or Do Not Disturb) still shows it unless the user turned that off
  /// for TimeMate in System Settings.
  static func content(
    forCompleted sessionType: SessionType, breakThroughFocus: Bool = true
  ) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = "TimeMate"
    let localizedSessionTitle = NSLocalizedString(
      sessionType.rawValue, comment: "The name of the current session type")
    content.subtitle = String(
      format: NSLocalizedString("%@ session complete!", comment: "Notification format string"),
      localizedSessionTitle
    )
    content.sound = nil
    content.categoryIdentifier = categoryIdentifier
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

  /// The request that shows the notification right away.
  static func request(
    forCompleted sessionType: SessionType, breakThroughFocus: Bool,
    identifier: String = UUID().uuidString
  ) -> UNNotificationRequest {
    UNNotificationRequest(
      identifier: identifier,
      content: content(forCompleted: sessionType, breakThroughFocus: breakThroughFocus),
      trigger: nil)
  }
}
