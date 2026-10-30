import AppKit
import UserNotifications

/// Tells the user why a global shortcut did nothing ("Already at the 180-minute limit"):
/// VoiceOver always reads it; a banner shows only when notifications are on in Settings
/// and allowed by macOS, otherwise the Mac beeps.
struct HotKeyMessage {
  var notificationsEnabled: () -> Bool
  /// Calls back with whether macOS lets TimeMate show banners.
  var checkAuthorized: (@escaping (Bool) -> Void) -> Void
  var post: (UNNotificationRequest) -> Void
  var beep: () -> Void
  var announce: (String) -> Void

  static let identifier = "hotKeyMessage"

  func show(_ message: String) {
    announce(message)
    guard notificationsEnabled() else {
      beep()
      return
    }
    let content = UNMutableNotificationContent()
    content.title = "TimeMate"
    content.body = message
    let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil)
    checkAuthorized { allowed in
      if allowed { post(request) } else { beep() }
    }
  }

  static func live(defaults: UserDefaults = .standard) -> HotKeyMessage {
    HotKeyMessage(
      notificationsEnabled: {
        defaults.object(forKey: SettingsKey.notificationsEnabled) as? Bool ?? true
      },
      checkAuthorized: { completion in
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          let status = settings.authorizationStatus
          let allowed =
            (status == .authorized || status == .provisional)
            && settings.alertSetting != .disabled
          DispatchQueue.main.async { completion(allowed) }
        }
      },
      post: { SessionNotification.post($0) },
      beep: { NSSound.beep() },
      announce: { message in
        NSAccessibility.post(
          element: NSApp as Any, notification: .announcementRequested,
          userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
          ])
      })
  }
}
