//  Created by homielab.com

import AppKit
import Carbon
import Combine
import SwiftUI

// MARK: - Actions

/// What a global keyboard shortcut does to the timer.
enum HotKeyAction: UInt32, CaseIterable, Identifiable {
  case startPause = 1
  case skip = 2
  case reset = 3

  var id: UInt32 { rawValue }

  /// Settings label of the action.
  var titleKey: LocalizedStringKey {
    switch self {
    case .startPause: return "Start / Pause"
    case .skip: return "Skip Session"
    case .reset: return "Reset Timer"
    }
  }

  /// Start/pause and skip are on from the start; reset only once the user
  /// turns it on, so a stray press can't throw away a running session.
  var isEnabledByDefault: Bool {
    self != .reset
  }

  /// ⌃⌥P, ⌃⌥S and ⌃⌥R: free in macOS and the common apps, easy to press.
  var defaultShortcut: HotKeyShortcut {
    switch self {
    case .startPause:
      return HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | optionKey))
    case .skip:
      return HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey))
    case .reset:
      return HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | optionKey))
    }
  }

  var keyCodeKey: String {
    switch self {
    case .startPause: return SettingsKey.hotKeyStartPauseKeyCode
    case .skip: return SettingsKey.hotKeySkipKeyCode
    case .reset: return SettingsKey.hotKeyResetKeyCode
    }
  }

  var modifiersKey: String {
    switch self {
    case .startPause: return SettingsKey.hotKeyStartPauseModifiers
    case .skip: return SettingsKey.hotKeySkipModifiers
    case .reset: return SettingsKey.hotKeyResetModifiers
    }
  }

  var enabledKey: String {
    switch self {
    case .startPause: return SettingsKey.hotKeyStartPauseEnabled
    case .skip: return SettingsKey.hotKeySkipEnabled
    case .reset: return SettingsKey.hotKeyResetEnabled
    }
  }
}

extension PomodoroTimer {
  /// Runs a global shortcut: start/pause toggles the timer (and continues past
  /// a break screen waiting for the user); skip moves to the next session;
  /// reset stops the timer and starts the current session over, like Reset in
  /// the popover and the menu bar item's menu.
  func perform(_ action: HotKeyAction) {
    switch action {
    case .startPause:
      if isWaitingToContinue {
        continueWork()
      } else if state == .active {
        pauseTimer()
      } else {
        startTimer()
      }
    case .skip:
      skipSession()
    case .reset:
      stopTimer()
    }
  }
}

// MARK: - Shortcut

/// A key combination: a virtual key code plus Carbon modifier flags
/// (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`), the format
/// `RegisterEventHotKey` takes and the one saved in user defaults.
struct HotKeyShortcut: Equatable {
  let keyCode: UInt32
  let modifiers: UInt32

  static let modifierMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)

  init(keyCode: UInt32, modifiers: UInt32) {
    self.keyCode = keyCode
    self.modifiers = modifiers & Self.modifierMask
  }

  init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
    var flags: UInt32 = 0
    if modifierFlags.contains(.command) { flags |= UInt32(cmdKey) }
    if modifierFlags.contains(.option) { flags |= UInt32(optionKey) }
    if modifierFlags.contains(.control) { flags |= UInt32(controlKey) }
    if modifierFlags.contains(.shift) { flags |= UInt32(shiftKey) }
    self.init(keyCode: UInt32(keyCode), modifiers: flags)
  }

  /// A global hot key takes the keystroke from every app, so it must include
  /// ⌘ or ⌃; otherwise (⌥E, ⇧A, a bare letter) it would block typing.
  var isValidGlobalHotKey: Bool {
    modifiers & UInt32(cmdKey | controlKey) != 0
  }

  /// "⌃⌥P", in the system's modifier order.
  var displayString: String { displayString(bundle: .main) }

  /// `displayString` with key names in the language of `bundle`.
  func displayString(bundle: Bundle) -> String {
    let symbols: [(Int, String)] = [
      (controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘"),
    ]
    let prefix = symbols.compactMap { modifiers & UInt32($0.0) != 0 ? $0.1 : nil }.joined()
    return prefix + Self.keyLabel(for: keyCode, bundle: bundle)
  }

  private static let keyLabels: [Int: String] = [
    kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
    kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
    kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
    kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
    kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
    kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
    kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
    kVK_ANSI_9: "9", kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
    kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
    kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
    kVK_ANSI_Grave: "`", kVK_Return: "↩", kVK_Tab: "⇥",
    kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_LeftArrow: "←",
    kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
    kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3",
    kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9",
    kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
  ]

  /// Keys shown by name rather than a symbol; the name is looked up in
  /// Localizable.strings ("Space" → "Dấu cách").
  private static let namedKeys: [Int: String] = [kVK_Space: "Space"]

  /// Label of a key in the app's language (`bundle` picks the language in tests).
  static func keyLabel(for keyCode: UInt32, bundle: Bundle = .main) -> String {
    if let name = namedKeys[Int(keyCode)] {
      return bundle.localizedString(forKey: name, value: name, table: nil)
    }
    return keyLabels[Int(keyCode)] ?? "#\(keyCode)"
  }
}

// MARK: - Manager

/// Global keyboard shortcuts for the timer.
///
/// Uses Carbon hot keys (`RegisterEventHotKey`), which work in the App Sandbox
/// without the Accessibility permission, unlike a global `NSEvent` monitor.
/// Shortcuts and their on/off switches are saved in user defaults.
final class HotKeyManager: ObservableObject {
  /// Signature of TimeMate's hot keys ("TMHK").
  fileprivate static let signature: OSType = 0x544D_484B

  @Published private(set) var shortcuts: [HotKeyAction: HotKeyShortcut] = [:]
  @Published private(set) var enabled: [HotKeyAction: Bool] = [:]
  /// Enabled actions whose shortcut could not be registered, usually because
  /// another app already owns the combination.
  @Published private(set) var failedActions: Set<HotKeyAction> = []
  /// True while Settings records a new combination; hot keys are paused then
  /// so the current combination can be recorded too.
  @Published private(set) var isRecording = false

  private let defaults: UserDefaults
  private let onAction: (HotKeyAction) -> Void
  private var hotKeyRefs: [HotKeyAction: EventHotKeyRef] = [:]
  private var eventHandlerRef: EventHandlerRef?
  private var isActive = false
  /// Hot keys held down, so key auto-repeat runs an action only once.
  private var pressedActions: Set<HotKeyAction> = []

  init(defaults: UserDefaults = .standard, onAction: @escaping (HotKeyAction) -> Void = { _ in }) {
    self.defaults = defaults
    self.onAction = onAction
    for action in HotKeyAction.allCases {
      shortcuts[action] = Self.loadShortcut(for: action, from: defaults)
      enabled[action] = Self.loadEnabled(for: action, from: defaults)
    }
  }

  deinit {
    unregisterAll()
    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
    }
  }

  // MARK: Persistence

  static func loadShortcut(for action: HotKeyAction, from defaults: UserDefaults)
    -> HotKeyShortcut
  {
    guard let keyCode = defaults.object(forKey: action.keyCodeKey) as? Int,
      let modifiers = defaults.object(forKey: action.modifiersKey) as? Int,
      let code = UInt32(exactly: keyCode), let flags = UInt32(exactly: modifiers)
    else { return action.defaultShortcut }
    let shortcut = HotKeyShortcut(keyCode: code, modifiers: flags)
    return shortcut.isValidGlobalHotKey ? shortcut : action.defaultShortcut
  }

  static func loadEnabled(for action: HotKeyAction, from defaults: UserDefaults) -> Bool {
    defaults.object(forKey: action.enabledKey) as? Bool ?? action.isEnabledByDefault
  }

  func shortcut(for action: HotKeyAction) -> HotKeyShortcut {
    shortcuts[action] ?? action.defaultShortcut
  }

  func isEnabled(_ action: HotKeyAction) -> Bool {
    enabled[action] ?? action.isEnabledByDefault
  }

  /// Saves a new combination and applies it right away. Combinations without
  /// ⌘ or ⌃ are refused (returns false).
  @discardableResult
  func setShortcut(_ shortcut: HotKeyShortcut, for action: HotKeyAction) -> Bool {
    guard shortcut.isValidGlobalHotKey else { return false }
    shortcuts[action] = shortcut
    defaults.set(Int(shortcut.keyCode), forKey: action.keyCodeKey)
    defaults.set(Int(shortcut.modifiers), forKey: action.modifiersKey)
    reregister()
    return true
  }

  func setEnabled(_ isOn: Bool, for action: HotKeyAction) {
    enabled[action] = isOn
    defaults.set(isOn, forKey: action.enabledKey)
    reregister()
  }

  // MARK: Recording

  func beginRecording() {
    isRecording = true
    unregisterHotKeys()
  }

  func endRecording() {
    isRecording = false
    reregister()
  }

  // MARK: Registration

  /// Registers every enabled shortcut and keeps them in sync with later
  /// changes. Main thread only.
  func activate() {
    isActive = true
    reregister()
  }

  func unregisterAll() {
    isActive = false
    unregisterHotKeys()
    failedActions = []
  }

  private func reregister() {
    unregisterHotKeys()
    guard isActive, !isRecording else { return }
    installEventHandlerIfNeeded()

    var failed: Set<HotKeyAction> = []
    for action in HotKeyAction.allCases where isEnabled(action) {
      let shortcut = self.shortcut(for: action)
      var ref: EventHotKeyRef?
      // Exclusive: a combination another app already registered fails here,
      // so Settings can say so instead of the shortcut silently not firing.
      let status = RegisterEventHotKey(
        shortcut.keyCode, shortcut.modifiers,
        EventHotKeyID(signature: Self.signature, id: action.rawValue),
        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
      if status == noErr, let ref {
        hotKeyRefs[action] = ref
      } else {
        failed.insert(action)
      }
    }
    failedActions = failed
  }

  private func unregisterHotKeys() {
    for ref in hotKeyRefs.values {
      UnregisterEventHotKey(ref)
    }
    hotKeyRefs.removeAll()
    pressedActions.removeAll()
  }

  private func installEventHandlerIfNeeded() {
    guard eventHandlerRef == nil else { return }
    var eventTypes = [
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
    ]
    InstallEventHandler(
      GetApplicationEventTarget(), hotKeyEventHandler, eventTypes.count, &eventTypes,
      Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
  }

  /// Called on the main thread for TimeMate's hot key events.
  fileprivate func handleHotKey(id: UInt32, pressed: Bool) -> Bool {
    guard let action = HotKeyAction(rawValue: id) else { return false }
    if !pressed {
      pressedActions.remove(action)
    } else if pressedActions.insert(action).inserted {
      onAction(action)
    }
    return true
  }
}

/// Carbon handler for hot key presses and releases; `userData` is the manager.
private let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
  guard let event, let userData else { return OSStatus(eventNotHandledErr) }
  var hotKeyID = EventHotKeyID()
  let status = GetEventParameter(
    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
  guard status == noErr, hotKeyID.signature == HotKeyManager.signature else {
    return OSStatus(eventNotHandledErr)
  }
  let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
  let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
  return manager.handleHotKey(id: hotKeyID.id, pressed: pressed)
    ? noErr : OSStatus(eventNotHandledErr)
}
