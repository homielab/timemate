//  Created by homielab.com

import SwiftUI

/// Restart, Reset, Start/Pause and Skip under the countdown.
struct ControlButtonsView: View {
  @EnvironmentObject var model: PopoverTimerModel

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
    HStack(spacing: 16) {
      Button {
        timer.restartCycle()
      } label: {
        Image(systemName: "backward.end.fill")
      }
      .buttonStyle(.bordered).controlSize(.large).accessibilityLabel("Restart")

      Button {
        timer.stopTimer()
      } label: {
        Image(systemName: "arrow.counterclockwise")
      }
      .buttonStyle(.bordered).controlSize(.large).disabled(model.state == .idle).accessibilityLabel(
        "Reset")

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
      .buttonStyle(.bordered).controlSize(.large).accessibilityLabel("Skip")
    }
  }
}
