//  Created by homielab.com

import SwiftUI

/// The popover's animations, which turn off when Reduce Motion is on.
enum PopoverMotion {
  enum Kind {
    /// The progress ring following the countdown.
    case progress
    /// The Settings button's chevron flipping.
    case settingsChevron
    /// The cycle dots fading into the cup on a long break.
    case longBreak
  }

  static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation? {
    guard !reduceMotion else { return nil }
    switch kind {
    case .progress: return .linear
    case .settingsChevron: return .easeInOut(duration: 0.3)
    case .longBreak: return .easeInOut(duration: 0.2)
    }
  }
}
