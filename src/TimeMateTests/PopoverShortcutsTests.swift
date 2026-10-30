//  Created by homielab.com

import AppKit
import XCTest

@testable import TimeMate

final class PopoverShortcutsTests: XCTestCase {
  private let space = PopoverShortcuts.spaceKeyCode

  func testSpaceAppliesWhenNothingTakesIt() {
    XCTAssertTrue(
      PopoverShortcuts.spaceStartsOrPauses(keyCode: space, modifiers: [], firstResponder: nil))
    XCTAssertTrue(
      PopoverShortcuts.spaceStartsOrPauses(
        keyCode: space, modifiers: [], firstResponder: NSView()))
  }

  func testSpaceIsLeftToTextFieldsAndButtons() {
    XCTAssertFalse(
      PopoverShortcuts.spaceStartsOrPauses(
        keyCode: space, modifiers: [], firstResponder: NSTextView()))
    XCTAssertFalse(
      PopoverShortcuts.spaceStartsOrPauses(
        keyCode: space, modifiers: [], firstResponder: NSTextField()))
    XCTAssertFalse(
      PopoverShortcuts.spaceStartsOrPauses(
        keyCode: space, modifiers: [], firstResponder: NSButton()))
  }

  func testSpaceIsTypedIntoTheSessionLabelField() {
    // A focused text field types through the window's field editor.
    let fieldEditor = NSTextView()
    fieldEditor.isFieldEditor = true
    XCTAssertFalse(
      PopoverShortcuts.spaceStartsOrPauses(
        keyCode: space, modifiers: [], firstResponder: fieldEditor))
  }

  func testOtherKeysAndModifiedSpaceDoNotApply() {
    XCTAssertFalse(
      PopoverShortcuts.spaceStartsOrPauses(keyCode: 0, modifiers: [], firstResponder: nil))
    XCTAssertFalse(
      PopoverShortcuts.spaceStartsOrPauses(
        keyCode: space, modifiers: [.command], firstResponder: nil))
  }

  private func asks(_ state: PomodoroState, done: Int = 0, waiting: Bool = false) -> Bool {
    PopoverShortcuts.restartNeedsConfirmation(
      state: state, focusSessionsCompleted: done, isWaitingToContinue: waiting)
  }

  func testRestartAsksWhenASessionIsInProgress() {
    XCTAssertTrue(asks(.active))
    XCTAssertTrue(asks(.paused))
  }

  func testRestartDoesNotAskOnAFreshCycle() {
    XCTAssertFalse(asks(.idle))
  }

  func testRestartAsksWhenIdleWithFocusSessionsDone() {
    XCTAssertTrue(asks(.idle, done: 3))
  }

  func testRestartAsksWhileTheBreakScreenWaits() {
    XCTAssertTrue(asks(.idle, waiting: true))
  }

  func testRestartWarningNamesWhatIsLost() {
    XCTAssertEqual(
      PopoverShortcuts.restartWarning(state: .idle), "Your progress in this cycle will be lost.")
    XCTAssertEqual(
      PopoverShortcuts.restartWarning(state: .active), "The session in progress will be lost.")
    let vi = Bundle(for: PomodoroTimer.self).path(forResource: "vi", ofType: "lproj")
      .flatMap(Bundle.init(path:))
    XCTAssertEqual(
      vi?.localizedString(
        forKey: "Your progress in this cycle will be lost.", value: nil, table: nil),
      "Tiến độ của chu kỳ này sẽ bị mất.")
  }
}
