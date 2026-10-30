//  Created by homielab.com

import Foundation

/// The optional "What are you working on?" label of a focus session.
enum SessionLabel {
  /// Longer labels are cut, so a pasted paragraph doesn't fill the history.
  static let maxLength = 80

  /// The label to store: trimmed, on one line, at most `maxLength` characters;
  /// `nil` when nothing is left.
  static func normalized(_ text: String?) -> String? {
    guard let text else { return nil }
    let oneLine = text.components(separatedBy: .newlines).joined(separator: " ")
    let trimmed = oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return String(trimmed.prefix(maxLength))
  }
}

/// Which label a focus session gets. A session that began without a label takes
/// the one typed while it runs (Start, then type, is the common way); one that
/// began with a label keeps it, so typing the next task before the bell labels
/// the next session only.
enum LabelAssignment {
  /// The label to record: the one captured at start, else the field as it stands.
  /// `started` is "" when the session began without a label, `nil` when it was
  /// not captured (a snapshot from an older version).
  static func label(started: String?, field: String?) -> String? {
    SessionLabel.normalized(started) ?? SessionLabel.normalized(field)
  }

  /// What editing the field does now, shown as the field's caption.
  enum Caption: Equatable {
    /// No focus session running or paused.
    case idle
    /// The running session has no label yet: the typed one becomes its label.
    case currentSession
    /// The running session has a label: edits apply from the next session.
    case nextSession

    var text: String {
      switch self {
      case .idle: String(localized: "Saved with each focus session you complete")
      case .currentSession: String(localized: "Saved with this focus session")
      case .nextSession: String(localized: "Applies from the next session")
      }
    }
  }

  static func caption(inFocusSession: Bool, started: String?) -> Caption {
    guard inFocusSession, let started else { return .idle }
    return SessionLabel.normalized(started) == nil ? .currentSession : .nextSession
  }
}
