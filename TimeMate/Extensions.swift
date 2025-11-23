//  Created by homielab.com

import Foundation
import SwiftUI

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

func restartApp() {
  let task = Process()
  task.launchPath = "/bin/sh"
  task.arguments = ["-c", "sleep 1 && open \"\(Bundle.main.bundlePath)\""]
  task.launch()
  NSApp.terminate(nil)
}

func resetAllSettings() {
  print("Resetting all user settings...")
  if let bundleID = Bundle.main.bundleIdentifier {
    UserDefaults.standard.removePersistentDomain(forName: bundleID)
    print("All settings have been reset. Restarting app.")
    restartApp()
  } else {
    print("Could not find bundle identifier to reset settings.")
  }
}

@objc extension UserDefaults {
  @objc dynamic var hideDockIcon: Bool {
    return bool(forKey: "hideDockIcon")
  }

  @objc dynamic var alwaysVisible: Bool {
    return bool(forKey: "alwaysVisible")
  }

  @objc dynamic var keepAwake: Bool {
    return bool(forKey: "keepAwake")
  }
}
