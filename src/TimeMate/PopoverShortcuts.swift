//  Created by homielab.com

import AppKit

/// Decisions for the popover's keyboard handling, kept free of views so they can be tested.
enum PopoverShortcuts {
  /// Space starts or pauses only when no control is using it: not while typing in a text
  /// field (the duration fields) and not on a focused button, where Space presses that button.
  static func spaceStartsOrPauses(
    keyCode: UInt16, modifiers: NSEvent.ModifierFlags, firstResponder: NSResponder?
  ) -> Bool {
    guard keyCode == spaceKeyCode else { return false }
    guard modifiers.intersection([.command, .control, .option, .shift]).isEmpty else {
      return false
    }
    return !consumesSpace(firstResponder)
  }

  static func consumesSpace(_ responder: NSResponder?) -> Bool {
    responder is NSText || responder is NSTextField || responder is NSControl
  }

  /// Restart throws away the cycle in progress, so it asks first unless nothing is running.
  static func restartNeedsConfirmation(state: PomodoroState) -> Bool {
    state != .idle
  }

  static let spaceKeyCode: UInt16 = 49
}
