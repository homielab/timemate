//  Created by homielab.com

import SwiftUI

/// Restart, Reset, Start/Pause and Skip under the countdown.
struct ControlButtonsView: View {
  @EnvironmentObject var model: PopoverTimerModel
  @State private var confirmingRestart = false

  private var timer: PomodoroTimer { model.timer }

  private var mainButtonIconName: String {
    switch model.mainAction {
    case .pause: return "pause.fill"
    case .start, .resume: return "play.fill"
    case .continueWork: return "arrow.right"
    }
  }

  private var mainButtonColor: Color {
    switch model.mainAction {
    case .pause: return .orange
    case .start, .resume, .continueWork: return .green
    }
  }

  private var mainButtonAccessibilityLabel: LocalizedStringKey {
    switch model.mainAction {
    case .pause: return "Pause"
    case .resume: return "Resume"
    case .start: return "Start"
    case .continueWork: return "Continue Work"
    }
  }

  var body: some View {
    VStack(spacing: 10) {
      controls
      if SessionSequence.offersFocusExtend(
        sessionType: model.currentSessionType, state: model.state)
      {
        Button {
          timer.extend(by: BreakOverlayAccessibility.extendMinutes)
        } label: {
          Text("+5 min")
        }
        .buttonStyle(.bordered).controlSize(.small)
        .disabled(!model.canExtend)
        .help(
          model.canExtend
            ? Text("Add 5 minutes to the focus session") : Text(verbatim: model.extendLimitText)
        )
        .accessibilityLabel("Add 5 minutes to the focus session")
        .accessibilityHint(Text(verbatim: model.canExtend ? "" : model.extendLimitText))
      }
    }
  }

  private var controls: some View {
    HStack(spacing: 16) {
      Button {
        if PopoverShortcuts.restartNeedsConfirmation(state: model.state) {
          confirmingRestart = true
        } else {
          timer.restartCycle()
        }
      } label: {
        Image(systemName: "backward.end.fill")
      }
      .buttonStyle(.bordered).controlSize(.large)
      .help("Restart the cycle from the first focus session")
      .accessibilityLabel("Restart")

      Button {
        timer.stopTimer()
      } label: {
        Image(systemName: "arrow.counterclockwise")
      }
      .buttonStyle(.bordered).controlSize(.large).disabled(model.state == .idle)
      .keyboardShortcut("r", modifiers: .command)
      .help("Reset (⌘R)")
      .accessibilityLabel("Reset")

      Button(action: model.performMainAction) {
        Image(systemName: mainButtonIconName)
      }
      .buttonStyle(.borderedProminent).tint(mainButtonColor).controlSize(.large)
      .help(mainButtonAccessibilityLabel)
      .accessibilityLabel(mainButtonAccessibilityLabel)

      Button {
        timer.skipSession()
      } label: {
        Image(systemName: "forward.end.fill")
      }
      .buttonStyle(.bordered).controlSize(.large)
      .keyboardShortcut(.rightArrow, modifiers: .command)
      .help("Skip (⌘→)")
      .accessibilityLabel("Skip")
    }
    .alert("Restart the cycle?", isPresented: $confirmingRestart) {
      Button("Restart", role: .destructive) { timer.restartCycle() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The session in progress will be lost.")
    }
  }
}
