//  Created by homielab.com

import SwiftUI

/// The top of the popover: session title, settings toggle, countdown, cycle dots
/// and today's statistics.
struct TimerDisplayView: View {
  @EnvironmentObject var model: PopoverTimerModel
  @Binding var settingsVisible: Bool
  @Binding var showProgressCircle: Bool

  @AppStorage(SettingsKey.longBreakInterval) private var longBreakInterval = 4

  private var style: SessionStyle { model.currentSessionType.style }

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        HStack(spacing: 6) {
          Image(systemName: style.iconName)
          Text(
            LocalizedStringKey(
              model.isBreakPostponed ? "Break postponed" : model.currentSessionType.rawValue))
        }
        .font(.headline)
        .foregroundColor(.secondary)

        Spacer()

        SettingsButton(settingsVisible: $settingsVisible)
      }

      CountdownView(
        countdown: model.countdown, accentColor: style.color,
        showProgressCircle: showProgressCircle)

      CycleIndicatorView(
        completed: model.focusSessionsCompleted,
        total: longBreakInterval,
        isLongBreak: model.currentSessionType == .longBreak
      )

      TodayStatsView(history: model.timer.history)
    }
  }
}

/// The remaining time and progress ring: the only part of the popover that
/// re-renders every second.
private struct CountdownView: View {
  @ObservedObject var countdown: PopoverCountdown
  let accentColor: Color
  let showProgressCircle: Bool

  var body: some View {
    if showProgressCircle {
      ZStack {
        Circle()
          .stroke(lineWidth: 12)
          .foregroundColor(Color(nsColor: .separatorColor))

        Circle()
          .stroke(lineWidth: 10)
          .foregroundColor(.gray.opacity(0.15))

        Circle().trim(from: 0.0, to: CGFloat(countdown.progress))
          .stroke(style: .init(lineWidth: 10, lineCap: .round, lineJoin: .round))
          .foregroundColor(accentColor)
          .rotationEffect(Angle(degrees: 270.0))
          .animation(.linear, value: countdown.progress)

        timeText
      }
      .frame(width: 120, height: 120)
    } else {
      timeText
    }
  }

  private var timeText: some View {
    Text(countdown.timeRemaining.toMinuteSecondString())
      .font(.system(size: 32, weight: .bold, design: .monospaced))
      .foregroundColor(accentColor)
  }
}

/// "Today: N pomodoros · X min" from the saved session history.
private struct TodayStatsView: View {
  @ObservedObject var history: SessionHistory

  var body: some View {
    let totals = history.todayTotals()
    Text(
      String(
        format: NSLocalizedString(
          "Today: %lld pomodoros · %lld min", comment: "Completed focus sessions and minutes today"),
        totals.pomodoros, totals.focusMinutes)
    )
    .font(.caption)
    .foregroundColor(.secondary)
    .monospacedDigit()
  }
}

private struct SettingsButton: View {
  @Binding var settingsVisible: Bool

  var body: some View {
    Button {
      settingsVisible.toggle()
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "gearshape.fill")
        Image(systemName: settingsVisible ? "chevron.up" : "chevron.down")
          .font(.system(size: 10, weight: .bold))
          .animation(.easeInOut(duration: 0.3), value: settingsVisible)
      }
      .padding(5)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundColor(.secondary)
    .background(Color.secondary.opacity(0.1))
    .cornerRadius(5)
  }
}

private struct CycleIndicatorView: View {
  let completed: Int
  let total: Int
  let isLongBreak: Bool

  var body: some View {
    ZStack {
      HStack(spacing: 6) {
        ForEach(1...total, id: \.self) { cycle in
          if cycle <= completed {
            Image(systemName: "checkmark.circle.fill")
          } else {
            Image(systemName: "circle")
          }
        }
      }
      .font(.system(size: 12))
      .foregroundColor(.secondary)
      .opacity(isLongBreak ? 0.0 : 1.0)

      Image(systemName: "cup.and.saucer.fill")
        .font(.callout)
        .foregroundColor(.secondary)
        .opacity(isLongBreak ? 1.0 : 0.0)
    }
    .frame(height: 20, alignment: .center)
    .animation(.easeInOut(duration: 0.2), value: isLongBreak)
  }
}
