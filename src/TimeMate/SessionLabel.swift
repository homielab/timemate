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
