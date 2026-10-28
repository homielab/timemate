//  Created by homielab.com

import Foundation

/// How a running session refreshes its countdown.
enum TickMode: Equatable {
  /// A tick every second, for a countdown somebody can see.
  case everySecond
  /// A tick whenever the minutes shown in the menu bar change ("12m").
  case everyMinute
  /// One wake-up when the session ends; nothing shows the countdown.
  case atEnd

  /// How late a tick may fire, so macOS can group it with other timers.
  static let tolerance: TimeInterval = 0.2

  /// Ticks every second only while the seconds are on screen: the popover is open,
  /// the menu bar shows them, the break screen is up, or VoiceOver may read the
  /// menu bar item. A menu bar with minutes only ticks once a minute. While the
  /// display is asleep or the screen is locked nobody can see any of it, so the
  /// timer only wakes up at the end of the session.
  static func mode(
    popoverOpen: Bool, menuBarStyle: MenuBarTimeStyle, breakOverlayShown: Bool,
    voiceOverRunning: Bool, screenAsleep: Bool = false
  ) -> TickMode {
    if screenAsleep { return .atEnd }
    if popoverOpen || breakOverlayShown || voiceOverRunning || menuBarStyle == .minutesSeconds {
      return .everySecond
    }
    return menuBarStyle == .minutesOnly ? .everyMinute : .atEnd
  }
}
