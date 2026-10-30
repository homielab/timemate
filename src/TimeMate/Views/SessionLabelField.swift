//  Created by homielab.com

import SwiftUI

/// One-line "What are you working on?" field shown during focus sessions. The
/// text is saved in the defaults, so it stays across relaunches, and goes with
/// every focus session that completes (history and notification); see
/// `LabelAssignment` for which session gets it.
struct SessionLabelField: View {
  @AppStorage(SettingsKey.sessionLabel) private var label = ""
  @FocusState private var isFocused: Bool
  @EnvironmentObject var model: PopoverTimerModel

  /// Tooltip and VoiceOver hint of the field: which session the label goes with.
  static func hint(for caption: LabelAssignment.Caption) -> String { caption.text }

  var body: some View {
    HStack(spacing: 2) {
      field
      recentMenu
    }
  }

  /// Labels of the latest focus sessions, to pick one instead of typing it again.
  private var recentMenu: some View {
    let labels = model.timer.history.recentLabels()
    return Menu {
      if labels.isEmpty {
        Text("No recent labels")
      } else {
        Section("Recent labels") {
          ForEach(labels, id: \.self) { recent in
            Button(recent) { label = recent }
          }
        }
        Divider()
        Button("Clear label") { label = "" }
          .disabled(label.isEmpty)
      }
    } label: {
      Image(systemName: "chevron.down")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Recent labels")
    .accessibilityLabel("Recent labels")
  }

  private var field: some View {
    TextField("What are you working on?", text: $label)
      .textFieldStyle(.roundedBorder)
      .multilineTextAlignment(.center)
      .controlSize(.small)
      .frame(maxWidth: 220)
      .focused($isFocused)
      // Return leaves the field, so Space starts and pauses the timer again.
      .onSubmit { isFocused = false }
      .onChange(of: label) { text in
        if text.count > SessionLabel.maxLength {
          label = String(text.prefix(SessionLabel.maxLength))
        }
      }
      .help(Self.hint(for: model.timer.labelCaption))
      .accessibilityLabel("What are you working on?")
      .accessibilityHint(Text(Self.hint(for: model.timer.labelCaption)))
  }
}
