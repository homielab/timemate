//  Created by homielab.com

import Foundation

/// Decisions behind the menu bar item's VoiceOver label, kept free of the
/// status item so they can be tested. Whether VoiceOver makes the timer tick
/// every second is `TickMode.mode(...)`'s call.
enum StatusItemPolicy {
  /// What the menu bar item's VoiceOver label shows.
  enum Label: Equatable {
    /// Follows the timer ("TimeMate, Focus, 12 minutes, 34 seconds remaining"),
    /// updated on every menu bar change.
    case followsTimer
    /// A fixed text that needs no updates.
    case fixed(String)
  }

  /// With VoiceOver on the label follows the timer; with it off nobody reads
  /// it, so it stays the app name and the menu bar does no extra work.
  static func label(voiceOverEnabled: Bool, appName: String) -> Label {
    voiceOverEnabled ? .followsTimer : .fixed(appName)
  }

  /// The label to set, or nil when the item already has it, so an unchanged
  /// label is not posted to the accessibility system again.
  static func labelUpdate(current: String?, new: String) -> String? {
    current == new ? nil : new
  }
}
