//  Created by homielab.com

import AppKit

/// Gives the keyboard back to the app the user worked in once the break screen or the
/// popover goes away. TimeMate has no regular window, so staying active after them would
/// swallow the user's typing until they click their app again.
final class FocusReturn {
  private var previous: NSRunningApplication?

  /// Which app to reactivate: the one in front before TimeMate took focus, only while
  /// TimeMate is still in front (the user did not switch apps meanwhile) and never
  /// TimeMate itself.
  static func appToReactivate(previous: pid_t?, frontmost: pid_t?, ownPID: pid_t) -> pid_t? {
    guard let previous, previous != ownPID, frontmost == ownPID else { return nil }
    return previous
  }

  /// Call right before `NSApp.activate`. Keeps the first app seen while TimeMate holds
  /// focus, so a second activation does not overwrite it with TimeMate.
  func remember() {
    guard let front = NSWorkspace.shared.frontmostApplication,
      front.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else { return }
    previous = front
  }

  /// Call once TimeMate's window is gone.
  func restore() {
    defer { previous = nil }
    let own = ProcessInfo.processInfo.processIdentifier
    guard
      Self.appToReactivate(
        previous: previous?.processIdentifier,
        frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier, ownPID: own) != nil,
      let previous, !previous.isTerminated
    else { return }
    if !previous.activate(options: []) { NSApp.hide(nil) }
  }
}

/// Height of the scrolling settings area of the popover: at most 450 pt, and short
/// enough that the whole popover fits the screen's visible frame.
enum PopoverLayout {
  static let settingsMaxHeight: CGFloat = 450
  static let screenMargin: CGFloat = 40
  static let settingsMinHeight: CGFloat = 120

  static func settingsHeight(visibleHeight: CGFloat?, topHeight: CGFloat) -> CGFloat {
    guard let visibleHeight else { return settingsMaxHeight }
    let room = visibleHeight - topHeight - screenMargin
    return max(settingsMinHeight, min(settingsMaxHeight, room))
  }
}
