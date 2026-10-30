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
  case extend = 4

  var id: UInt32 { rawValue }

  /// Settings label of the action.
  var titleKey: LocalizedStringKey { LocalizedStringKey(title(bundle: .main)) }

  /// The label in the language of `bundle`, for messages that name the action.
  func title(bundle: Bundle) -> String {
    let name: String
    switch self {
    case .startPause: name = "Start / Pause"
    case .skip: name = "Skip Session"
    case .reset: name = "Reset Timer"
    case .extend: name = "Add 5 Minutes"
    }
    return bundle.localizedString(forKey: name, value: name, table: nil)
  }

  /// Start/pause and skip are on from the start; reset and extend only once
  /// the user turns them on, so a stray press can't change a running session.
  var isEnabledByDefault: Bool {
    self == .startPause || self == .skip
  }

  /// ⌃⌥P, ⌃⌥S, ⌃⌥R and ⌃⌥E: free in macOS and the common apps, easy to press.
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
    case .extend:
      return HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(controlKey | optionKey))
    }
  }

  var keyCodeKey: String {
    switch self {
    case .startPause: return SettingsKey.hotKeyStartPauseKeyCode
    case .skip: return SettingsKey.hotKeySkipKeyCode
    case .reset: return SettingsKey.hotKeyResetKeyCode
    case .extend: return SettingsKey.hotKeyExtendKeyCode
    }
  }

  var modifiersKey: String {
    switch self {
    case .startPause: return SettingsKey.hotKeyStartPauseModifiers
    case .skip: return SettingsKey.hotKeySkipModifiers
    case .reset: return SettingsKey.hotKeyResetModifiers
    case .extend: return SettingsKey.hotKeyExtendModifiers
    }
  }

  var enabledKey: String {
    switch self {
    case .startPause: return SettingsKey.hotKeyStartPauseEnabled
    case .skip: return SettingsKey.hotKeySkipEnabled
    case .reset: return SettingsKey.hotKeyResetEnabled
    case .extend: return SettingsKey.hotKeyExtendEnabled
    }
  }
}

extension PomodoroTimer {
  /// Runs a global shortcut: start/pause toggles the timer (and continues past
  /// a break screen waiting for the user); skip moves to the next session;
  /// reset stops the timer and starts the current session over, like Reset in
  /// the popover and the menu bar item's menu; extend adds 5 minutes to the
  /// running or paused session, like "+5 min" (nothing when idle). Returns a
  /// message to show when the action could not run because of the 180-minute
  /// limit, or because the break screen's skip delay is not over (skip and pause
  /// then do nothing and beep).
  @discardableResult
  func perform(_ action: HotKeyAction) -> String? {
    if action == .skip || (action == .startPause && state == .active && !isWaitingToContinue),
      skipLockSeconds > 0
    {
      NSSound.beep()
      return skipLockText
    }
    switch action {
    case .startPause:
      if state == .active && !isWaitingToContinue {
        pauseTimer()
      } else {
        startOrContinue()
      }
    case .skip:
      skipSession()
    case .reset:
      return TimerIntentActions.recordedText(seconds: stopTimer(recording: true))
    case .extend:
      let result = TimerIntentActions.extend(self, minutes: BreakOverlayAccessibility.extendMinutes)
      if case .atLimit = result { return TimerIntentActions.extendText(result) }
    }
    return nil
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

  /// ⌘ alone (or ⇧⌘) with a letter, digit, symbol, Space or Tab: apps use these for
  /// their own commands (⌘S, ⌘N, ⌘C, …), and a global hot key would take them from every
  /// app. Adding ⌃ or ⌥, or using a function key (F1–F20), makes it safe.
  var isReserved: Bool {
    let commandOnly = modifiers & ~UInt32(shiftKey) == UInt32(cmdKey)
    return commandOnly && !Self.functionKeys.contains(Int(keyCode))
  }

  private static let functionKeys: Set<Int> = [
    kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
    kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
  ]

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

  /// "Control Option P": the shortcut as VoiceOver should say it, since "⌃⌥P" is read as symbols.
  var spokenString: String { spokenString(bundle: .main) }

  func spokenString(bundle: Bundle) -> String {
    let names: [(Int, String)] = [
      (controlKey, "Control"), (optionKey, "Option"), (shiftKey, "Shift"), (cmdKey, "Command"),
    ]
    let modifierNames = names.compactMap { modifiers & UInt32($0.0) != 0 ? $0.1 : nil }
      .map { bundle.localizedString(forKey: $0, value: $0, table: nil) }
    return (modifierNames + [Self.spokenKeyName(for: keyCode, bundle: bundle)])
      .joined(separator: " ")
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
    kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14",
    kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
    kVK_F20: "F20",
  ]

  /// Keypad keys, shown as "Keypad 1" so they differ from the main row's "1".
  /// Clear and Enter are words and get translated.
  private static let keypadKeys: [Int: String] = [
    kVK_ANSI_Keypad0: "0", kVK_ANSI_Keypad1: "1", kVK_ANSI_Keypad2: "2",
    kVK_ANSI_Keypad3: "3", kVK_ANSI_Keypad4: "4", kVK_ANSI_Keypad5: "5",
    kVK_ANSI_Keypad6: "6", kVK_ANSI_Keypad7: "7", kVK_ANSI_Keypad8: "8",
    kVK_ANSI_Keypad9: "9", kVK_ANSI_KeypadDecimal: ".", kVK_ANSI_KeypadMultiply: "*",
    kVK_ANSI_KeypadPlus: "+", kVK_ANSI_KeypadDivide: "/", kVK_ANSI_KeypadMinus: "-",
    kVK_ANSI_KeypadEquals: "=", kVK_ANSI_KeypadClear: "Clear", kVK_ANSI_KeypadEnter: "Enter",
  ]

  /// Words VoiceOver says for keys whose label is a symbol ("↩", "←"), looked
  /// up in Localizable.strings; the visible label keeps the symbol.
  private static let spokenNames: [Int: String] = [
    kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
    kVK_ForwardDelete: "Forward Delete", kVK_Escape: "Escape", kVK_LeftArrow: "Left Arrow",
    kVK_RightArrow: "Right Arrow", kVK_UpArrow: "Up Arrow", kVK_DownArrow: "Down Arrow",
    kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
  ]

  /// Keys shown by name rather than a symbol; the name is looked up in
  /// Localizable.strings ("Space" → "Dấu cách").
  private static let namedKeys: [Int: String] = [kVK_Space: "Space"]

  /// Label of a key in the app's language (`bundle` picks the language in tests).
  static func keyLabel(for keyCode: UInt32, bundle: Bundle = .main) -> String {
    if let name = namedKeys[Int(keyCode)] {
      return bundle.localizedString(forKey: name, value: name, table: nil)
    }
    if let key = keypadKeys[Int(keyCode)] {
      let name = bundle.localizedString(forKey: key, value: key, table: nil)
      let format = bundle.localizedString(forKey: "Keypad %@", value: "Keypad %@", table: nil)
      return String(format: format, name)
    }
    return keyLabels[Int(keyCode)] ?? "#\(keyCode)"
  }

  /// Name of a key as VoiceOver should say it: a word for symbol keys, else its label.
  static func spokenKeyName(for keyCode: UInt32, bundle: Bundle = .main) -> String {
    if let name = spokenNames[Int(keyCode)] {
      return bundle.localizedString(forKey: name, value: name, table: nil)
    }
    return keyLabel(for: keyCode, bundle: bundle)
  }
}

/// Outcome of `HotKeyManager.setShortcut`.
enum HotKeyAssignment: Equatable {
  case ok
  /// Needs ⌘ or ⌃ (see `HotKeyShortcut.isValidGlobalHotKey`).
  case invalid
  /// A system-wide shortcut such as ⌘V (see `HotKeyShortcut.isReserved`).
  case reserved
  /// Another action of TimeMate already uses the combination.
  case conflict(HotKeyAction)
}

// MARK: - Manager

/// Registers and unregisters one Carbon hot key. Tests use a fake so they
/// neither take the user's real shortcuts nor depend on other running apps.
struct HotKeyRegistrar {
  /// Returns the registered hot key, or nil when the system refused it.
  var register: (HotKeyShortcut, HotKeyAction) -> EventHotKeyRef?
  var unregister: (EventHotKeyRef) -> Void

  static let carbon = HotKeyRegistrar(
    register: { shortcut, action in
      var ref: EventHotKeyRef?
      // Exclusive: a combination another app already registered fails here,
      // so Settings can say so instead of the shortcut silently not firing.
      let status = RegisterEventHotKey(
        shortcut.keyCode, shortcut.modifiers,
        EventHotKeyID(signature: HotKeyManager.signature, id: action.rawValue),
        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
      return status == noErr ? ref : nil
    },
    unregister: { UnregisterEventHotKey($0) })
}

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

  /// Seconds after `activate()` at which shortcuts that failed are tried again.
  /// A restart briefly runs two copies of the app, and the old one still holds
  /// the shortcuts when the new one starts.
  static let retryDelays: [TimeInterval] = [1, 3, 10]

  private let defaults: UserDefaults
  private let onAction: (HotKeyAction) -> Void
  private let registrar: HotKeyRegistrar
  private let schedule: (TimeInterval, @escaping () -> Void) -> Void
  /// Bumped by `activate()` and `unregisterAll()` so older retries do nothing.
  private var retryGeneration = 0
  private var hotKeyRefs: [HotKeyAction: EventHotKeyRef] = [:]
  private var eventHandlerRef: EventHandlerRef?
  private var isActive = false
  /// Hot keys held down, so key auto-repeat runs an action only once.
  private var pressedActions: Set<HotKeyAction> = []

  init(
    defaults: UserDefaults = .standard,
    registrar: HotKeyRegistrar = .carbon,
    schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    },
    onAction: @escaping (HotKeyAction) -> Void = { _ in }
  ) {
    self.defaults = defaults
    self.registrar = registrar
    self.schedule = schedule
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
    return shortcut.isValidGlobalHotKey && !shortcut.isReserved ? shortcut : action.defaultShortcut
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

  /// Saves a new combination and applies it right away. Refused, with the
  /// reason, when it lacks ⌘ or ⌃, is reserved by macOS, or is the combination
  /// of another enabled action (so two actions never fight over one key). A
  /// turned-off action does not hold on to its combination.
  @discardableResult
  func setShortcut(_ shortcut: HotKeyShortcut, for action: HotKeyAction) -> HotKeyAssignment {
    guard shortcut.isValidGlobalHotKey else { return .invalid }
    guard !shortcut.isReserved else { return .reserved }
    if let other = enabledAction(using: shortcut, besides: action) {
      return .conflict(other)
    }
    shortcuts[action] = shortcut
    defaults.set(Int(shortcut.keyCode), forKey: action.keyCodeKey)
    defaults.set(Int(shortcut.modifiers), forKey: action.modifiersKey)
    reregister()
    return .ok
  }

  /// Turns an action's shortcut on or off. Turning it on is refused with
  /// `.conflict` while another enabled action uses the same combination; the
  /// action then stays off.
  @discardableResult
  func setEnabled(_ isOn: Bool, for action: HotKeyAction) -> HotKeyAssignment {
    if isOn, let other = enabledAction(using: shortcut(for: action), besides: action) {
      return .conflict(other)
    }
    enabled[action] = isOn
    defaults.set(isOn, forKey: action.enabledKey)
    reregister()
    return .ok
  }

  private func enabledAction(using shortcut: HotKeyShortcut, besides action: HotKeyAction)
    -> HotKeyAction?
  {
    HotKeyAction.allCases.first {
      $0 != action && isEnabled($0) && self.shortcut(for: $0) == shortcut
    }
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
  /// changes; shortcuts that fail are tried again after `retryDelays`.
  /// Main thread only.
  func activate() {
    isActive = true
    reregister()
    retryGeneration += 1
    scheduleRetry(index: 0, generation: retryGeneration)
  }

  func unregisterAll() {
    isActive = false
    retryGeneration += 1
    unregisterHotKeys()
    failedActions = []
  }

  /// Tries again to register the shortcuts that failed, e.g. once another copy
  /// of the app has quit. Does nothing when none failed or while inactive or
  /// recording.
  func retryFailed() {
    guard isActive, !isRecording, !failedActions.isEmpty else { return }
    reregister()
  }

  private func scheduleRetry(index: Int, generation: Int) {
    guard index < Self.retryDelays.count, !failedActions.isEmpty else { return }
    let elapsed = index == 0 ? 0 : Self.retryDelays[index - 1]
    schedule(Self.retryDelays[index] - elapsed) { [weak self] in
      guard let self, self.retryGeneration == generation else { return }
      self.retryFailed()
      self.scheduleRetry(index: index + 1, generation: generation)
    }
  }

  private func reregister() {
    unregisterHotKeys()
    guard isActive, !isRecording else { return }
    installEventHandlerIfNeeded()

    var failed: Set<HotKeyAction> = []
    for action in HotKeyAction.allCases where isEnabled(action) {
      if let ref = registrar.register(shortcut(for: action), action) {
        hotKeyRefs[action] = ref
      } else {
        failed.insert(action)
      }
    }
    failedActions = failed
  }

  private func unregisterHotKeys() {
    for ref in hotKeyRefs.values {
      registrar.unregister(ref)
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
