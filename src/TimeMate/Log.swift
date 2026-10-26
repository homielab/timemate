//  Created by homielab.com

import Foundation
import os

extension Logger {
  private static let subsystem = Bundle.main.bundleIdentifier ?? "TimeMate"

  /// App lifecycle and settings (Console.app: subsystem = the bundle id).
  static let app = Logger(subsystem: subsystem, category: "app")
  /// Session history file.
  static let history = Logger(subsystem: subsystem, category: "history")
}
