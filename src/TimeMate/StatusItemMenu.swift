//  Created by homielab.com

import AppKit
import Foundation

/// Decisions behind the menu bar item's right-click menu and its VoiceOver
/// label, kept free of windows and views so they can be tested.
enum StatusItemMenu {
  /// A right click, or a Control-click, on the menu bar item opens the menu;
  /// any other click toggles the popover.
  static func opensMenu(eventType: NSEvent.EventType?, modifierFlags: NSEvent.ModifierFlags)
    -> Bool
  {
    switch eventType {
    case .rightMouseDown, .rightMouseUp:
      return true
    case .leftMouseDown, .leftMouseUp:
      return modifierFlags.contains(.control)
    default:
      return false
    }
  }

  /// Title of the start/pause item; it runs `PomodoroTimer.perform(.startPause)`.
  static func startPauseTitle(state: PomodoroState, isWaitingToContinue: Bool) -> String {
    if isWaitingToContinue {
      return NSLocalizedString("Continue Work", comment: "Status item menu")
    }
    switch state {
    case .active: return NSLocalizedString("Pause", comment: "Status item menu")
    case .paused: return NSLocalizedString("Resume", comment: "Status item menu")
    case .idle: return NSLocalizedString("Start", comment: "Status item menu")
    }
  }

  /// Reset only makes sense once a session has started, as in the popover.
  static func isResetEnabled(state: PomodoroState) -> Bool {
    state != .idle
  }

  /// What VoiceOver reads for the menu bar item, e.g.
  /// "TimeMate, Focus, 12 minutes, 34 seconds remaining".
  static func accessibilityLabel(
    sessionType: SessionType, state: PomodoroState, secondsRemaining: Int,
    isBreakPostponed: Bool, isWaitingToContinue: Bool
  ) -> String {
    let session = NSLocalizedString(
      isBreakPostponed ? "Break postponed" : sessionType.rawValue, comment: "")
    let remaining = BreakOverlayAccessibility.countdownValue(secondsRemaining: secondsRemaining)
    if isWaitingToContinue {
      return String(
        format: NSLocalizedString("TimeMate, %@ finished", comment: "VoiceOver label"), session)
    }
    let format: String
    switch state {
    case .active:
      format = NSLocalizedString("TimeMate, %1$@, %2$@ remaining", comment: "VoiceOver label")
    case .paused:
      format = NSLocalizedString(
        "TimeMate, %1$@, paused, %2$@ remaining", comment: "VoiceOver label")
    case .idle:
      format = NSLocalizedString("TimeMate, %1$@, ready, %2$@", comment: "VoiceOver label")
    }
    return String(format: format, session, remaining)
  }
}
