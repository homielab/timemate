//  Created by homielab.com

import SwiftUI

/// The top of the popover: session title, settings toggle, countdown, cycle dots,
/// the focus session's label and today's statistics.
struct TimerDisplayView: View {
  @EnvironmentObject var model: PopoverTimerModel
  @Binding var settingsVisible: Bool
  @Binding var showProgressCircle: Bool

  @AppStorage(SettingsKey.longBreakInterval) private var longBreakInterval =
    SessionCycle.defaultInterval

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
        total: SessionCycle.sanitizedInterval(longBreakInterval),
        isLongBreak: model.currentSessionType == .longBreak
      )

      if model.currentSessionType == .focus {
        SessionLabelField()
      }

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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
          .animation(
            PopoverMotion.animation(.progress, reduceMotion: reduceMotion),
            value: countdown.progress)

        timeText
      }
      .frame(width: 120, height: 120)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(ringSpeech.label))
      .accessibilityValue(Text(ringSpeech.value))
    } else {
      timeText
        .accessibilityLabel(Text(plainSpeech.label))
        .accessibilityValue(Text(plainSpeech.value))
    }
  }

  private var ringSpeech: (label: String, value: String) {
    SessionCycle.clockAccessibility(
      secondsRemaining: countdown.timeRemaining, progress: countdown.progress)
  }

  private var plainSpeech: (label: String, value: String) {
    SessionCycle.clockAccessibility(secondsRemaining: countdown.timeRemaining, progress: nil)
  }

  private var timeText: some View {
    Text(countdown.timeRemaining.toMinuteSecondString())
      .font(.system(size: 32, weight: .bold, design: .monospaced))
      .foregroundColor(accentColor)
  }
}

/// "Today: N pomodoros · X min" from the saved session history; with a daily
/// goal "Today: N/G pomodoros · X min" above a small progress bar.
private struct TodayStatsView: View {
  @ObservedObject var history: SessionHistory
  @EnvironmentObject var appDelegate: AppDelegate
  @AppStorage(SettingsKey.dailyGoal) private var storedGoal = DailyGoal.off
  @AppStorage(SettingsKey.streakSkipsWeekends) private var skipWeekends = false

  var body: some View {
    let totals = history.todayTotals()
    let summary = TodaySummary(
      pomodoros: totals.pomodoros, minutes: totals.focusMinutes, goal: storedGoal,
      streak: {
        history.goalStreak(goal: DailyGoal.sanitized(storedGoal), skipWeekends: skipWeekends)
      })
    if !summary.hasGoal {
      Text(summary.visibleText)
        .font(.caption)
        .foregroundColor(.secondary)
        .monospacedDigit()
    } else {
      VStack(spacing: 4) {
        HStack(spacing: 4) {
          if summary.reached {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.green)
          }
          Text(summary.visibleText)
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .monospacedDigit()

        ProgressView(value: summary.progress)
          .progressViewStyle(.linear)
          .tint(summary.reached ? .green : .accentColor)
          .controlSize(.small)
          .frame(width: 140)

        if summary.showsStreak {
          Label(summary.streakText, systemImage: "flame.fill")
            .font(.caption)
            .foregroundColor(.secondary)
            .monospacedDigit()
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(summary.accessibilityLabel))
      // The extra line changes the popover's height; resize it in one step.
      .onChange(of: summary.showsStreak) { _ in appDelegate.updatePopoverSize() }
    }
  }
}

private struct SettingsButton: View {
  @Binding var settingsVisible: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button {
      settingsVisible.toggle()
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "gearshape.fill")
        Image(systemName: settingsVisible ? "chevron.up" : "chevron.down")
          .font(.system(size: 10, weight: .bold))
          .animation(
            PopoverMotion.animation(.settingsChevron, reduceMotion: reduceMotion),
            value: settingsVisible)
      }
      .padding(5)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundColor(.secondary)
    .background(Color.secondary.opacity(0.1))
    .cornerRadius(5)
    .keyboardShortcut(",", modifiers: .command)
    .help("Settings (⌘,)")
    .accessibilityLabel("Settings")
    .accessibilityValue(settingsVisible ? Text("Expanded") : Text("Collapsed"))
  }
}

private struct CycleIndicatorView: View {
  let completed: Int
  let total: Int
  let isLongBreak: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    .animation(
      PopoverMotion.animation(.longBreak, reduceMotion: reduceMotion),
      value: isLongBreak
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Text(
        SessionCycle.accessibilityLabel(
          completed: completed, total: total, isLongBreak: isLongBreak)))
  }
}
