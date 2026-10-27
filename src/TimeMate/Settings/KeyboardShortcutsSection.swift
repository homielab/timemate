//  Created by homielab.com

import AppKit
import SwiftUI

struct KeyboardShortcutsSection: View {
  @EnvironmentObject var hotKeys: HotKeyManager
  /// Why the last combination recorded for an action was refused.
  @State private var refusals: [HotKeyAction: HotKeyAssignment] = [:]

  var body: some View {
    SettingsSection(titleKey: "Keyboard Shortcuts", systemImage: "keyboard") {
      ForEach(HotKeyAction.allCases) { action in
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(action.titleKey)
            Spacer(minLength: 12)
            HotKeyRecorder(action: action, refusal: refusalBinding(for: action))
              .disabled(!hotKeys.isEnabled(action))
            Toggle(isOn: enabledBinding(for: action)) { EmptyView() }
              .toggleStyle(.switch)
              .fixedSize()
              .accessibilityLabel(Text(action.titleKey))
          }
          if let message = refusalMessage(for: action) {
            Text(message)
              .font(.caption)
              .foregroundColor(.orange)
          } else if hotKeys.failedActions.contains(action) {
            Text("This shortcut is used by another app. Record a different one.")
              .font(.caption)
              .foregroundColor(.orange)
          }
        }
      }
      Text("Works in any app. Click a shortcut, then press a new combination with ⌃ or ⌘.")
        .font(.caption)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func refusalBinding(for action: HotKeyAction) -> Binding<HotKeyAssignment?> {
    Binding(get: { refusals[action] }, set: { refusals[action] = $0 })
  }

  private func refusalMessage(for action: HotKeyAction) -> String? {
    switch refusals[action] {
    case .reserved:
      return NSLocalizedString("Reserved by macOS. Record a different one.", comment: "")
    case .conflict(let other):
      return String(
        format: NSLocalizedString("Already used by %@. Record a different one.", comment: ""),
        other.title(bundle: .main))
    default:
      return nil
    }
  }

  private func enabledBinding(for action: HotKeyAction) -> Binding<Bool> {
    Binding(
      get: { hotKeys.isEnabled(action) },
      set: { hotKeys.setEnabled($0, for: action) }
    )
  }
}

/// A button showing a shortcut; click it, then press a combination to record it.
/// Escape or a second click cancels. Uses a local key monitor, so no permission
/// is needed: the popover is the key window while recording.
private struct HotKeyRecorder: View {
  @EnvironmentObject var hotKeys: HotKeyManager
  let action: HotKeyAction
  @Binding var refusal: HotKeyAssignment?
  @State private var keyMonitor: Any?

  private var isRecording: Bool { keyMonitor != nil }

  var body: some View {
    Button {
      isRecording ? stopRecording() : startRecording()
    } label: {
      if isRecording {
        Text(refusal == .invalid ? "Add ⌃ or ⌘" : "Press keys…")
          .frame(minWidth: 70)
      } else {
        Text(verbatim: hotKeys.shortcut(for: action).displayString)
          .monospaced()
          .frame(minWidth: 70)
      }
    }
    .controlSize(.small)
    .disabled(hotKeys.isRecording && !isRecording)
    .help("Click to record a new shortcut")
    .accessibilityLabel(
      String(format: NSLocalizedString("%@ shortcut", comment: ""), action.title(bundle: .main))
    )
    .accessibilityValue(isRecording ? "" : hotKeys.shortcut(for: action).spokenString)
    .onDisappear(perform: stopRecording)
    // Recording ended elsewhere (the popover closed): drop the key monitor too.
    .onChange(of: hotKeys.isRecording) { if !$0 { stopRecording() } }
  }

  private func startRecording() {
    guard keyMonitor == nil else { return }
    refusal = nil
    hotKeys.beginRecording()
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      // 53 = Escape.
      if event.keyCode == 53, flags.isDisjoint(with: [.command, .control]) {
        stopRecording()
        return nil
      }
      let shortcut = HotKeyShortcut(keyCode: event.keyCode, modifierFlags: flags)
      let result = hotKeys.setShortcut(shortcut, for: action)
      if result == .ok {
        stopRecording()
      } else {
        refusal = result
      }
      return nil
    }
  }

  private func stopRecording() {
    guard let keyMonitor else { return }
    NSEvent.removeMonitor(keyMonitor)
    self.keyMonitor = nil
    refusal = nil
    if hotKeys.isRecording { hotKeys.endRecording() }
  }
}
