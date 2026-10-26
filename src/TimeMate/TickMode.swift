//  Created by homielab.com

import Foundation

/// How a running session refreshes its countdown.
enum TickMode: Equatable {
  /// A tick every second, for a countdown somebody can see.
  case everySecond
  /// One wake-up when the session ends; nothing shows the seconds.
  case atEnd

  /// How late a tick may fire, so macOS can group it with other timers.
  static let tolerance: TimeInterval = 0.2

  /// Ticks every second only while the time is on screen: the popover is open,
  /// the menu bar shows the time, the break screen is up, or VoiceOver may read
  /// the menu bar item.
  static func mode(
    popoverOpen: Bool, menuBarShowsTime: Bool, breakOverlayShown: Bool, voiceOverRunning: Bool
  ) -> TickMode {
    popoverOpen || menuBarShowsTime || breakOverlayShown || voiceOverRunning
      ? .everySecond : .atEnd
  }
}
