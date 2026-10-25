//  Created by homielab.com

import SwiftUI

/// Restart, Reset, Start/Pause and Skip under the countdown.
struct ControlButtonsView: View {
  @EnvironmentObject var model: PopoverTimerModel

  private var timer: PomodoroTimer { model.timer }

  private var mainButtonIconName: String {
    switch model.state {
    case .active: return "pause.fill"
    case .paused, .idle: return "play.fill"
    }
  }

  private var mainButtonColor: Color {
    switch model.state {
    case .active: return .orange
    case .paused, .idle: return .green
    }
  }

  private var mainButtonAccessibilityLabel: LocalizedStringKey {
    switch model.state {
    case .active: return "Pause"
    case .paused: return "Resume"
    case .idle: return "Start"
    }
  }

  private var mainButtonAction: () -> Void {
    switch model.state {
    case .active: return timer.pauseTimer
    case .paused, .idle: return timer.startTimer
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

      Button(action: mainButtonAction) {
        Image(systemName: mainButtonIconName)
      }
      .buttonStyle(.borderedProminent).tint(mainButtonColor).controlSize(.large)
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
