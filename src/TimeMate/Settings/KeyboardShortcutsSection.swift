//  Created by homielab.com

import AppKit
import SwiftUI

struct KeyboardShortcutsSection: View {
  @EnvironmentObject var hotKeys: HotKeyManager

  var body: some View {
    SettingsSection(titleKey: "Keyboard Shortcuts", systemImage: "keyboard") {
      ForEach(HotKeyAction.allCases) { action in
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(action.titleKey)
            Spacer(minLength: 12)
            HotKeyRecorder(action: action)
              .disabled(!hotKeys.isEnabled(action))
            Toggle(isOn: enabledBinding(for: action)) { EmptyView() }
              .toggleStyle(.switch)
              .fixedSize()
              .accessibilityLabel(Text(action.titleKey))
          }
          if hotKeys.failedActions.contains(action) {
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
  @State private var keyMonitor: Any?
  @State private var needsModifier = false

  private var isRecording: Bool { keyMonitor != nil }

  var body: some View {
    Button {
      isRecording ? stopRecording() : startRecording()
    } label: {
      if isRecording {
        Text(needsModifier ? "Add ⌃ or ⌘" : "Press keys…")
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
    .onDisappear(perform: stopRecording)
  }

  private func startRecording() {
    guard keyMonitor == nil else { return }
    needsModifier = false
    hotKeys.beginRecording()
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      // 53 = Escape.
      if event.keyCode == 53, flags.isDisjoint(with: [.command, .control]) {
        stopRecording()
        return nil
      }
      let shortcut = HotKeyShortcut(keyCode: event.keyCode, modifierFlags: flags)
      if hotKeys.setShortcut(shortcut, for: action) {
        stopRecording()
      } else {
        needsModifier = true
      }
      return nil
    }
  }

  private func stopRecording() {
    guard let keyMonitor else { return }
    NSEvent.removeMonitor(keyMonitor)
    self.keyMonitor = nil
    needsModifier = false
    hotKeys.endRecording()
  }
}
