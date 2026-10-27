//  Created by homielab.com

import SwiftUI

/// One-line "What are you working on?" field shown during focus sessions. The
/// text is saved in the defaults, so it stays across relaunches, and goes with
/// every focus session that completes (history and notification).
struct SessionLabelField: View {
  @AppStorage(SettingsKey.sessionLabel) private var label = ""
  @FocusState private var isFocused: Bool

  var body: some View {
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
      .help("Saved with each focus session you complete")
      .accessibilityLabel("What are you working on?")
  }
}
