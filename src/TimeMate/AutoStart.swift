//  Created by homielab.com

import Foundation

/// Whether the next session starts by itself, decided per kind of session.
/// Breaks and focus sessions have their own switch; one that was never set
/// follows the older single "Auto-start next session" value, so people who
/// upgrade keep the behaviour they had.
struct AutoStart: Equatable {
  var breaks: Bool
  var focus: Bool

  /// Both switches on: the default, and what a fresh install gets.
  static let `default` = AutoStart(breaks: true, focus: true)

  /// Whether the session `next` starts without a click.
  func shouldStart(next: SessionType) -> Bool {
    SessionSequence.isBreak(next) ? breaks : focus
  }

  /// Reads the switches. An unset switch inherits `autoStartNextSession`, which
  /// is on when it was never set either.
  init(defaults: UserDefaults) {
    let legacy = defaults.object(forKey: SettingsKey.autoStartNextSession) as? Bool ?? true
    breaks = defaults.object(forKey: SettingsKey.autoStartBreaks) as? Bool ?? legacy
    focus = defaults.object(forKey: SettingsKey.autoStartFocus) as? Bool ?? legacy
  }

  init(breaks: Bool, focus: Bool) {
    self.breaks = breaks
    self.focus = focus
  }
}
