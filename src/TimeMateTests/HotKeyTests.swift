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
    let shortcut = HotKeyShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey))
    XCTAssertEqual(manager.setShortcut(shortcut, for: .reset), .ok)

    let reloaded = HotKeyManager(defaults: defaults)
    XCTAssertTrue(reloaded.isEnabled(.reset))
    XCTAssertEqual(reloaded.shortcut(for: .reset), shortcut)
    XCTAssertEqual(defaults.integer(forKey: SettingsKey.hotKeyResetKeyCode), kVK_Space)
  }

  // MARK: - Key names

  func testSpokenStringNamesModifiersInWords() throws {
    let shortcut = HotKeyAction.startPause.defaultShortcut
    XCTAssertEqual(shortcut.spokenString(bundle: try bundle("en")), "Control Option P")
    let withCommand = HotKeyShortcut(
      keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey))
    XCTAssertEqual(withCommand.spokenString(bundle: try bundle("en")), "Shift Command Space")
    XCTAssertEqual(withCommand.spokenString(bundle: try bundle("vi")), "Shift Command Dấu cách")
  }

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

  func testSymbolKeysAreSpokenByName() throws {
    let left = HotKeyShortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey))
    XCTAssertEqual(left.spokenString(bundle: try bundle("en")), "Control Left Arrow")
    XCTAssertEqual(left.spokenString(bundle: try bundle("vi")), "Control Mũi tên trái")
    XCTAssertEqual(left.displayString(bundle: try bundle("vi")), "⌃←")
    let named = [
      kVK_Return, kVK_Tab, kVK_Delete, kVK_ForwardDelete, kVK_Escape, kVK_LeftArrow,
      kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
    ]
    for keyCode in named {
      let spoken = HotKeyShortcut.spokenKeyName(for: UInt32(keyCode), bundle: try bundle("en"))
      XCTAssertTrue(spoken.allSatisfy { $0.isLetter || $0 == " " }, spoken)
    }
  }

  func testKeypadAndHighFunctionKeysHaveLabels() throws {
    let keypad = HotKeyShortcut(
      keyCode: UInt32(kVK_ANSI_Keypad1), modifiers: UInt32(controlKey | cmdKey))
    XCTAssertFalse(keypad.displayString.contains("#"))
    XCTAssertEqual(keypad.displayString(bundle: try bundle("en")), "⌃⌘Keypad 1")
    XCTAssertEqual(keypad.spokenString(bundle: try bundle("en")), "Control Command Keypad 1")
    XCTAssertEqual(
      HotKeyShortcut.keyLabel(for: UInt32(kVK_ANSI_KeypadEnter), bundle: try bundle("en")),
      "Keypad Enter")
    let keys = [
      kVK_ANSI_Keypad0, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4, kVK_ANSI_Keypad5,
      kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9,
      kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus,
      kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadEquals, kVK_ANSI_KeypadClear,
      kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]
    for keyCode in keys {
      let label = HotKeyShortcut.keyLabel(for: UInt32(keyCode), bundle: try bundle("vi"))
      XCTAssertFalse(label.hasPrefix("#"), "key \(keyCode)")
    }
    XCTAssertEqual(HotKeyShortcut.keyLabel(for: UInt32(kVK_F20)), "F20")
  }

  func testSymbolKeysStayTheSameInEveryLanguage() throws {
    XCTAssertEqual(
      HotKeyShortcut.keyLabel(for: UInt32(kVK_Return), bundle: try bundle("vi")), "↩")
    XCTAssertEqual(HotKeyShortcut.keyLabel(for: UInt32(kVK_ANSI_P), bundle: try bundle("vi")), "P")
  }

  func testShortcutIsSavedAsKeyCodeAndModifiersAndReloaded() {
    let manager = HotKeyManager(defaults: defaults)
    let shortcut = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | shiftKey))
    XCTAssertEqual(manager.setShortcut(shortcut, for: .skip), .ok)

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
    XCTAssertEqual(manager.setShortcut(shortcut, for: .startPause), .invalid)
    XCTAssertEqual(manager.shortcut(for: .startPause), HotKeyAction.startPause.defaultShortcut)
    XCTAssertNil(defaults.object(forKey: SettingsKey.hotKeyStartPauseKeyCode))
  }

  func testShortcutOfAnotherActionIsRefusedWithItsName() {
    let manager = HotKeyManager(defaults: defaults)
    let startPause = HotKeyAction.startPause.defaultShortcut
    XCTAssertEqual(manager.setShortcut(startPause, for: .skip), .conflict(.startPause))
    XCTAssertEqual(manager.shortcut(for: .skip), HotKeyAction.skip.defaultShortcut)
    XCTAssertNil(defaults.object(forKey: SettingsKey.hotKeySkipKeyCode))
    // The action's own combination is not a conflict.
    XCTAssertEqual(manager.setShortcut(startPause, for: .startPause), .ok)
    XCTAssertEqual(HotKeyAction.startPause.title(bundle: .main), "Start / Pause")
  }

  func testConflictNamesTheActionInBothLanguages() throws {
    XCTAssertEqual(HotKeyAction.skip.title(bundle: try bundle("en")), "Skip Session")
    XCTAssertNotEqual(
      HotKeyAction.skip.title(bundle: try bundle("vi")),
      HotKeyAction.skip.title(bundle: try bundle("en")))
  }

  func testReservedSystemShortcutsAreRefused() {
    let manager = HotKeyManager(defaults: defaults)
    let reserved = [
      kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_Z, kVK_ANSI_A, kVK_ANSI_Q, kVK_ANSI_W,
      kVK_ANSI_H, kVK_ANSI_Comma, kVK_Space, kVK_Tab,
    ]
    for key in reserved {
      let shortcut = HotKeyShortcut(keyCode: UInt32(key), modifiers: UInt32(cmdKey))
      XCTAssertTrue(shortcut.isReserved, "key \(key)")
      XCTAssertEqual(manager.setShortcut(shortcut, for: .startPause), .reserved, "key \(key)")
    }
    XCTAssertEqual(manager.shortcut(for: .startPause), HotKeyAction.startPause.defaultShortcut)
    XCTAssertNil(defaults.object(forKey: SettingsKey.hotKeyStartPauseKeyCode))
  }

  func testOtherCombinationsAreNotReserved() {
    let notReserved = [
      HotKeyShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)),
      HotKeyShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey)),
      HotKeyShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey)),
      HotKeyShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey)),
    ]
    let manager = HotKeyManager(defaults: defaults)
    for shortcut in notReserved {
      XCTAssertFalse(shortcut.isReserved)
      XCTAssertEqual(manager.setShortcut(shortcut, for: .startPause), .ok)
    }
  }

  func testReservedSavedShortcutFallsBackToDefault() {
    defaults.set(kVK_ANSI_V, forKey: SettingsKey.hotKeySkipKeyCode)
    defaults.set(cmdKey, forKey: SettingsKey.hotKeySkipModifiers)
    XCTAssertEqual(
      HotKeyManager.loadShortcut(for: .skip, from: defaults), HotKeyAction.skip.defaultShortcut)
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

  // MARK: - Retrying failed shortcuts

  /// Stands in for Carbon: combinations in `taken` are refused, others succeed.
  private final class FakeHotKeys {
    var taken: Set<HotKeyAction> = []
    var registered: Set<HotKeyAction> = []
    var registerCalls = 0
    var scheduled: [(delay: TimeInterval, work: () -> Void)] = []

    var registrar: HotKeyRegistrar {
      HotKeyRegistrar(
        register: { [weak self] _, action in
          guard let self else { return nil }
          self.registerCalls += 1
          guard !self.taken.contains(action) else { return nil }
          self.registered.insert(action)
          return OpaquePointer(bitPattern: Int(action.rawValue))
        },
        unregister: { [weak self] ref in
          let id = UInt32(Int(bitPattern: UnsafeRawPointer(ref)))
          if let action = HotKeyAction(rawValue: id) { self?.registered.remove(action) }
        })
    }

    func schedule(_ delay: TimeInterval, _ work: @escaping () -> Void) {
      scheduled.append((delay, work))
    }

    /// Runs the oldest pending retry and returns its delay.
    @discardableResult
    func runNext() -> TimeInterval? {
      guard !scheduled.isEmpty else { return nil }
      let next = scheduled.removeFirst()
      next.work()
      return next.delay
    }
  }

  private func makeManager(_ fake: FakeHotKeys) -> HotKeyManager {
    HotKeyManager(defaults: defaults, registrar: fake.registrar, schedule: fake.schedule)
  }

  func testRetryFailedRegistersShortcutsFreedByAnotherApp() {
    let fake = FakeHotKeys()
    fake.taken = [.startPause, .skip]
    let manager = makeManager(fake)
    manager.activate()
    XCTAssertEqual(manager.failedActions, [.startPause, .skip])

    fake.taken = []
    manager.retryFailed()

    XCTAssertTrue(manager.failedActions.isEmpty)
    XCTAssertEqual(fake.registered, [.startPause, .skip])
  }

  func testRetryFailedDoesNothingBeforeActivate() {
    let fake = FakeHotKeys()
    let manager = makeManager(fake)
    manager.retryFailed()
    XCTAssertEqual(fake.registerCalls, 0)
    XCTAssertTrue(fake.registered.isEmpty)
  }

  func testRetryFailedDoesNothingWhenNothingFailed() {
    let fake = FakeHotKeys()
    let manager = makeManager(fake)
    manager.activate()
    let calls = fake.registerCalls
    manager.retryFailed()
    XCTAssertEqual(fake.registerCalls, calls)
    XCTAssertTrue(fake.scheduled.isEmpty, "no retries scheduled when everything registered")
  }

  func testRetriesRunAfterOneThreeAndTenSecondsThenStop() {
    let fake = FakeHotKeys()
    fake.taken = [.startPause]
    let manager = makeManager(fake)
    manager.activate()

    var elapsed: TimeInterval = 0
    var times: [TimeInterval] = []
    while let delay = fake.runNext() {
      elapsed += delay
      times.append(elapsed)
    }
    XCTAssertEqual(times, [1, 3, 10])
    XCTAssertEqual(manager.failedActions, [.startPause])
    XCTAssertEqual(fake.registered, [.skip])
  }

  func testRetriesStopOnceTheShortcutIsFree() {
    let fake = FakeHotKeys()
    fake.taken = [.startPause]
    let manager = makeManager(fake)
    manager.activate()

    fake.taken = []
    XCTAssertEqual(fake.runNext(), 1)

    XCTAssertTrue(manager.failedActions.isEmpty)
    XCTAssertEqual(fake.registered, [.startPause, .skip])
    XCTAssertTrue(fake.scheduled.isEmpty)
  }

  func testRetriesStopAfterUnregisterAll() {
    let fake = FakeHotKeys()
    fake.taken = [.startPause]
    let manager = makeManager(fake)
    manager.activate()
    manager.unregisterAll()
    fake.taken = []
    let calls = fake.registerCalls

    fake.runNext()

    XCTAssertEqual(fake.registerCalls, calls)
    XCTAssertTrue(fake.scheduled.isEmpty)
  }

  func testRetryWaitsWhileRecording() {
    let fake = FakeHotKeys()
    fake.taken = [.skip]
    let manager = makeManager(fake)
    manager.activate()
    manager.beginRecording()
    fake.taken = []

    manager.retryFailed()
    XCTAssertTrue(fake.registered.isEmpty)

    manager.endRecording()
    XCTAssertTrue(manager.failedActions.isEmpty)
    XCTAssertEqual(fake.registered, [.startPause, .skip])
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
