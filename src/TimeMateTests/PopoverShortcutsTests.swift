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

  func testRestartAsksOnlyWhenASessionIsInProgress() {
    XCTAssertFalse(PopoverShortcuts.restartNeedsConfirmation(state: .idle))
    XCTAssertTrue(PopoverShortcuts.restartNeedsConfirmation(state: .active))
    XCTAssertTrue(PopoverShortcuts.restartNeedsConfirmation(state: .paused))
  }
}
