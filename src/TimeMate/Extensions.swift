//  Created by homielab.com

import Foundation
import SwiftUI
import os

extension Int {
  func toMinuteSecondString() -> String {
    String(format: "%02d:%02d", self / 60, self % 60)
  }
}

extension Bundle {
  public var appName: String {
    getInfo("CFBundleName")
  }
  public var displayName: String {
    getInfo("CFBundleDisplayName")
  }
  public var language: String {
    getInfo("CFBundleDevelopmentRegion")
  }
  public var identifier: String {
    getInfo("CFBundleIdentifier")
  }
  public var copyright: String {
    getInfo("NSHumanReadableCopyright").replacingOccurrences(of: "\\\\n", with: "\n")
  }

  public var appBuild: String {
    getInfo("CFBundleVersion")
  }
  public var appVersion: String {
    getInfo("CFBundleShortVersionString")
  }

  fileprivate func getInfo(_ str: String) -> String {
    infoDictionary?[str] as? String ?? "n/a"
  }
}

/// Relaunches the app through Launch Services (no shell, so it works in the
/// sandbox), then quits this instance. The timer hands over first (last snapshot,
/// no more ticks), so the two instances never both end or record the session.
/// `failureMessage`: what the alert says when the new instance can't start.
func restartApp(
  failureMessage: String = NSLocalizedString(
    "Quit TimeMate and open it again to apply the change.", comment: ""),
  timer: PomodoroTimer = .shared,
  open: (_ completion: @escaping (Error?) -> Void) -> Void = openNewInstance,
  onFailure: @escaping (String) -> Void = showRestartFailedAlert,
  terminate: @escaping () -> Void = { NSApp.terminate(nil) }
) {
  timer.prepareForRelaunch()
  open { error in
    DispatchQueue.main.async {
      if let error {
        Logger.app.error("Could not relaunch the app: \(error.localizedDescription)")
        timer.cancelRelaunch()
        onFailure(failureMessage)
      } else {
        terminate()
      }
    }
  }
}

func openNewInstance(_ completion: @escaping (Error?) -> Void) {
  let configuration = NSWorkspace.OpenConfiguration()
  // Without this, Launch Services would just bring the running instance forward.
  configuration.createsNewApplicationInstance = true
  NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) {
    _, error in completion(error)
  }
}

func showRestartFailedAlert(message: String) {
  let alert = NSAlert()
  alert.alertStyle = .warning
  alert.messageText = NSLocalizedString("TimeMate couldn't restart", comment: "")
  alert.informativeText = message
  NSApp.activate(ignoringOtherApps: true)
  alert.runModal()
}

/// Defaults keys that hold app state rather than settings; a reset keeps them.
enum SettingsReset {
  static let preservedKeys = [
    SettingsKey.timerSnapshot, SettingsKey.dailyGoalNotifiedAt,
    SettingsKey.dailyGoalNotifiedGoal, SettingsKey.hasLaunchedBefore,
    SettingsKey.sessionLabel,
  ]

  /// Clears every setting but keeps the running session, the date of the last
  /// daily-goal notification, the first-launch marker and the session label.
  static func perform(on defaults: UserDefaults, domain: String) {
    let kept = preservedKeys.compactMap { key in
      defaults.object(forKey: key).map { (key, $0) }
    }
    defaults.removePersistentDomain(forName: domain)
    for (key, value) in kept {
      defaults.set(value, forKey: key)
    }
  }
}

func resetAllSettings() {
  if let bundleID = Bundle.main.bundleIdentifier {
    SettingsReset.perform(on: .standard, domain: bundleID)
    LoginItemReset.perform()
    Logger.app.notice("All settings have been reset, restarting")
    restartApp(
      failureMessage: NSLocalizedString(
        "Settings were reset. Please open TimeMate again.", comment: "Reset relaunch failed"))
  } else {
    Logger.app.error("Could not reset settings: no bundle identifier")
  }
}

@objc extension UserDefaults {
  @objc dynamic var hideDockIcon: Bool {
    return bool(forKey: SettingsKey.hideDockIcon)
  }

  @objc dynamic var alwaysVisible: Bool {
    return bool(forKey: SettingsKey.alwaysVisible)
  }

  @objc dynamic var keepAwake: Bool {
    return bool(forKey: SettingsKey.keepAwake)
  }
}
