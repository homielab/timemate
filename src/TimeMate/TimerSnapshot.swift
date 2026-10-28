//  Created by homielab.com

import Foundation

/// What `PomodoroTimer` saves in user defaults whenever it changes, so a
/// running, paused or postponed session survives quitting, an update or a crash.
struct TimerSnapshot: Codable, Equatable {
  var state: PomodoroState
  var sessionType: SessionType
  /// When the running session (or the postponed break) ends; `nil` unless active.
  var endDate: Date?
  /// Seconds left; what a paused session resumes with.
  var remaining: Int
  /// Length of the current session in seconds, including "+5 min" extensions.
  var totalDuration: Int
  var focusSessionsCompleted: Int
  var isBreakPostponed: Bool
  var isWaitingToContinue: Bool
  /// The label typed when the session began ("" = none). `nil` in snapshots saved
  /// before this field existed: the label field is read as it stands then.
  var label: String?

  /// Whether the values make sense together; anything else is treated as damaged.
  var isValid: Bool {
    guard remaining >= 0, totalDuration > 0, focusSessionsCompleted >= 0 else { return false }
    switch state {
    case .idle: return endDate == nil
    case .active: return endDate != nil
    case .paused: return endDate == nil && remaining > 0
    }
  }

  /// The saved snapshot, or `nil` when there is none. A damaged one is removed.
  static func load(from defaults: UserDefaults) -> TimerSnapshot? {
    guard defaults.object(forKey: SettingsKey.timerSnapshot) != nil else { return nil }
    guard let data = defaults.data(forKey: SettingsKey.timerSnapshot),
      let snapshot = try? JSONDecoder().decode(TimerSnapshot.self, from: data),
      snapshot.isValid
    else {
      defaults.removeObject(forKey: SettingsKey.timerSnapshot)
      return nil
    }
    return snapshot
  }

  func save(to defaults: UserDefaults) {
    guard let data = try? JSONEncoder().encode(self) else { return }
    defaults.set(data, forKey: SettingsKey.timerSnapshot)
  }
}
