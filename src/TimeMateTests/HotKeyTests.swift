//  Created by homielab.com

import AppKit
import Carbon
import XCTest

@testable import TimeMate

final class HotKeyTests: XCTestCase {
  private static let suiteName = "TimeMateHotKeyTests"
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
  }

  override func tearDown() {
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  // MARK: - Shortcut

  func testDefaultShortcutsAreControlOptionPAndS() {
    XCTAssertEqual(HotKeyAction.startPause.defaultShortcut.displayString, "⌃⌥P")
    XCTAssertEqual(HotKeyAction.skip.defaultShortcut.displayString, "⌃⌥S")
    XCTAssertEqual(HotKeyAction.reset.defaultShortcut.displayString, "⌃⌥R")
    XCTAssertEqual(HotKeyAction.startPause.defaultShortcut.keyCode, UInt32(kVK_ANSI_P))
    XCTAssertEqual(
      HotKeyAction.skip.defaultShortcut.modifiers, UInt32(controlKey | optionKey))
  }

  func testEventModifierFlagsMapToCarbonFlags() {
    let shortcut = HotKeyShortcut(
      keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.command, .shift, .capsLock, .function])
    XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_K))
    XCTAssertEqual(shortcut.modifiers, UInt32(cmdKey | shiftKey))
    XCTAssertEqual(shortcut.displayString, "⇧⌘K")
  }

  func testUnknownKeyCodeStillHasALabel() {
    XCTAssertEqual(HotKeyShortcut(keyCode: 200, modifiers: UInt32(cmdKey)).displayString, "⌘#200")
  }

  func testGlobalHotKeyNeedsCommandOrControl() {
    XCTAssertTrue(HotKeyShortcut(keyCode: 1, modifiers: UInt32(controlKey)).isValidGlobalHotKey)
    XCTAssertTrue(HotKeyShortcut(keyCode: 1, modifiers: UInt32(cmdKey)).isValidGlobalHotKey)
    XCTAssertFalse(
      HotKeyShortcut(keyCode: 1, modifiers: UInt32(optionKey | shiftKey)).isValidGlobalHotKey)
    XCTAssertFalse(HotKeyShortcut(keyCode: 1, modifiers: 0).isValidGlobalHotKey)
  }

  // MARK: - Persistence

  func testMissingDefaultsGiveDefaultShortcutsAndOnlyResetOff() {
    let manager = HotKeyManager(defaults: defaults)
    for action in HotKeyAction.allCases {
      XCTAssertEqual(manager.shortcut(for: action), action.defaultShortcut)
    }
    XCTAssertTrue(manager.isEnabled(.startPause))
    XCTAssertTrue(manager.isEnabled(.skip))
    XCTAssertFalse(manager.isEnabled(.reset))
  }

  func testResetShortcutCanBeTurnedOnAndRecorded() {
    let manager = HotKeyManager(defaults: defaults)
    manager.setEnabled(true, for: .reset)
    let shortcut = HotKeyShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
    XCTAssertTrue(manager.setShortcut(shortcut, for: .reset))

    let reloaded = HotKeyManager(defaults: defaults)
    XCTAssertTrue(reloaded.isEnabled(.reset))
    XCTAssertEqual(reloaded.shortcut(for: .reset), shortcut)
    XCTAssertEqual(defaults.integer(forKey: SettingsKey.hotKeyResetKeyCode), kVK_Space)
  }

  // MARK: - Key names

  private func bundle(_ localization: String) throws -> Bundle {
    let path = try XCTUnwrap(
      Bundle(for: PomodoroTimer.self).path(forResource: localization, ofType: "lproj"))
    return try XCTUnwrap(Bundle(path: path))
  }

  func testSpaceKeyIsNamedInTheAppLanguage() throws {
    let space = UInt32(kVK_Space)
    XCTAssertEqual(HotKeyShortcut.keyLabel(for: space, bundle: try bundle("en")), "Space")
    XCTAssertEqual(HotKeyShortcut.keyLabel(for: space, bundle: try bundle("vi")), "Dấu cách")
    let shortcut = HotKeyShortcut(keyCode: space, modifiers: UInt32(controlKey | optionKey))
    XCTAssertEqual(shortcut.displayString(bundle: try bundle("vi")), "⌃⌥Dấu cách")
  }

  func testSymbolKeysStayTheSameInEveryLanguage() throws {
    XCTAssertEqual(
      HotKeyShortcut.keyLabel(for: UInt32(kVK_Return), bundle: try bundle("vi")), "↩")
    XCTAssertEqual(HotKeyShortcut.keyLabel(for: UInt32(kVK_ANSI_P), bundle: try bundle("vi")), "P")
  }

  func testShortcutIsSavedAsKeyCodeAndModifiersAndReloaded() {
    let manager = HotKeyManager(defaults: defaults)
    let shortcut = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | shiftKey))
    XCTAssertTrue(manager.setShortcut(shortcut, for: .skip))

    XCTAssertEqual(defaults.integer(forKey: SettingsKey.hotKeySkipKeyCode), kVK_ANSI_J)
    XCTAssertEqual(defaults.integer(forKey: SettingsKey.hotKeySkipModifiers), cmdKey | shiftKey)
    XCTAssertEqual(HotKeyManager(defaults: defaults).shortcut(for: .skip), shortcut)
    XCTAssertEqual(
      HotKeyManager(defaults: defaults).shortcut(for: .startPause),
      HotKeyAction.startPause.defaultShortcut)
  }

  func testShortcutWithoutCommandOrControlIsRefused() {
    let manager = HotKeyManager(defaults: defaults)
    let shortcut = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(optionKey))
    XCTAssertFalse(manager.setShortcut(shortcut, for: .startPause))
    XCTAssertEqual(manager.shortcut(for: .startPause), HotKeyAction.startPause.defaultShortcut)
    XCTAssertNil(defaults.object(forKey: SettingsKey.hotKeyStartPauseKeyCode))
  }

  func testInvalidSavedShortcutFallsBackToDefault() {
    defaults.set(kVK_ANSI_E, forKey: SettingsKey.hotKeyStartPauseKeyCode)
    defaults.set(optionKey, forKey: SettingsKey.hotKeyStartPauseModifiers)
    XCTAssertEqual(
      HotKeyManager.loadShortcut(for: .startPause, from: defaults),
      HotKeyAction.startPause.defaultShortcut)
  }

  func testDisablingIsSavedPerAction() {
    let manager = HotKeyManager(defaults: defaults)
    manager.setEnabled(false, for: .startPause)
    XCTAssertEqual(defaults.object(forKey: SettingsKey.hotKeyStartPauseEnabled) as? Bool, false)

    let reloaded = HotKeyManager(defaults: defaults)
    XCTAssertFalse(reloaded.isEnabled(.startPause))
    XCTAssertTrue(reloaded.isEnabled(.skip))
  }

  func testInactiveManagerRegistersNothing() {
    let manager = HotKeyManager(defaults: defaults)
    manager.setEnabled(true, for: .skip)
    XCTAssertTrue(manager.failedActions.isEmpty)
  }

  // MARK: - Actions on the timer

  private func makeTimer(autoStart: Bool = true, keepBreakOpen: Bool = false) -> PomodoroTimer {
    defaults.set(3, forKey: SettingsKey.focusDuration)
    defaults.set(2, forKey: SettingsKey.shortBreakDuration)
    defaults.set(autoStart, forKey: SettingsKey.autoStartNextSession)
    defaults.set(keepBreakOpen, forKey: SettingsKey.keepBreakScreenOpen)
    defaults.set(false, forKey: SettingsKey.notificationsEnabled)
    defaults.set(0.0, forKey: SettingsKey.alarmVolume)
    return PomodoroTimer(
      defaults: defaults, now: { Date(timeIntervalSince1970: 1_000_000) },
      workspaceNotificationCenter: NotificationCenter(), isFullscreenProbe: { false })
  }

  func testStartPauseTogglesTheTimer() {
    let timer = makeTimer()
    timer.perform(.startPause)
    XCTAssertEqual(timer.state, .active)
    timer.perform(.startPause)
    XCTAssertEqual(timer.state, .paused)
    timer.perform(.startPause)
    XCTAssertEqual(timer.state, .active)
  }

  func testStartPauseContinuesFromWaitingBreakScreen() {
    let timer = makeTimer(autoStart: false, keepBreakOpen: true)
    timer.currentSessionType = .shortBreak
    timer.isWaitingToContinue = true

    timer.perform(.startPause)

    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
  }

  func testResetStopsTheTimerAndRestartsTheSession() {
    let timer = makeTimer()
    timer.perform(.startPause)
    timer.perform(.reset)
    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.timeRemaining, 3)
    XCTAssertEqual(timer.progress, 1.0)
  }

  func testSkipMovesToNextSession() {
    let timer = makeTimer()
    timer.perform(.skip)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.focusSessionsCompleted, 0)  // skipped while idle: not counted
  }
}
