//  Created by homielab.com

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StatisticsSection: View {
  @EnvironmentObject var model: PopoverTimerModel
  @AppStorage(SettingsKey.dailyGoal) private var dailyGoal = DailyGoal.off
  @State private var showingResetAlert = false

  var body: some View {
    SettingsSection(titleKey: "Statistics", systemImage: "chart.bar.fill") {
      DailyGoalRow(goal: $dailyGoal)

      WeekStatisticsView(history: model.timer.history, goal: DailyGoal.sanitized(dailyGoal))

      MenuItemButton(title: "Export CSV…", systemImage: "square.and.arrow.up") {
        StatisticsExporter.export(
          model.timer.history.statisticsCSV(goal: DailyGoal.sanitized(dailyGoal)))
      }

      MenuItemButton(title: "Reset Statistics", systemImage: "trash") {
        showingResetAlert = true
      }
      .alert("Reset Statistics?", isPresented: $showingResetAlert) {
        Button("Reset", role: .destructive) {
          model.timer.history.reset()
        }
        Button("Cancel", role: .cancel) {
        }
      } message: {
        Text("This will delete the history of completed sessions. Are you sure?")
      }
    }
  }
}

/// Daily goal: "Off" or 1–24 pomodoros, set with a stepper.
private struct DailyGoalRow: View {
  @Binding var goal: Int

  private var valueText: Text {
    let value = DailyGoal.sanitized(goal)
    return value == DailyGoal.off ? Text("Off") : Text(verbatim: "\(value)")
  }

  var body: some View {
    HStack {
      Text("Daily goal")
      Spacer(minLength: 12)
      valueText
        .monospacedDigit()
        .foregroundColor(.secondary)
        .frame(width: 52, alignment: .trailing)
      Stepper("", value: $goal, in: DailyGoal.off...DailyGoal.range.upperBound)
        .labelsHidden()
        .accessibilityLabel(Text("Daily goal"))
        .accessibilityValue(valueText)
    }
    .help("Pomodoros to finish each day. TimeMate tells you once when you reach it.")
  }
}

/// One row per day of the last seven days, then the week's totals and the change
/// against the seven days before. With a daily goal, days that met it get a
/// check mark and the week shows on how many days it was met.
private struct WeekStatisticsView: View {
  @ObservedObject var history: SessionHistory
  let goal: Int

  var body: some View {
    let week = history.weekStatistics()
    let maxPomodoros = max(1, week.days.map(\.pomodoros).max() ?? 0)
    let totals = week.totals
    let previous = week.previousTotals

    VStack(alignment: .leading, spacing: 4) {
      Text("Last 7 days")
        .font(.caption)
        .foregroundColor(.secondary)

      ForEach(week.days, id: \.date) { day in
        DayRow(
          day: day, fraction: Double(day.pomodoros) / Double(maxPomodoros), goal: goal,
          calendar: history.calendar)
      }

      Divider().padding(.vertical, 2)

      Text(StatisticsText.week(pomodoros: totals.pomodoros, minutes: totals.focusMinutes))
        .font(.callout.weight(.semibold))
        .monospacedDigit()

      Text(
        StatisticsText.change(
          pomodoros: totals.pomodoros - previous.pomodoros,
          minutes: totals.focusMinutes - previous.focusMinutes)
      )
      .font(.caption)
      .foregroundColor(.secondary)
      .monospacedDigit()

      if goal > DailyGoal.off {
        Text(
          StatisticsText.goalDays(
            reached: SessionStatistics.daysReachingGoal(week.days, goal: goal),
            of: week.days.count)
        )
        .font(.caption)
        .foregroundColor(.secondary)
        .monospacedDigit()
      }
    }
  }
}

private struct DayRow: View {
  let day: SessionStatistics.Day
  let fraction: Double
  let goal: Int
  let calendar: Calendar

  private var goalReached: Bool { DailyGoal.isReached(completed: day.pomodoros, goal: goal) }

  var body: some View {
    HStack(spacing: 8) {
      Text(StatisticsFormat.dayLabel(day.date, calendar: calendar))
        .frame(width: 70, alignment: .leading)
        .lineLimit(1)

      GeometryReader { proxy in
        RoundedRectangle(cornerRadius: 2)
          .fill(Color.accentColor.opacity(day.pomodoros == 0 ? 0 : 0.8))
          .frame(width: max(0, proxy.size.width * fraction))
      }
      .frame(height: 8)

      Text(verbatim: "\(day.pomodoros)")
        .frame(width: 24, alignment: .trailing)
      if goal > DailyGoal.off {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.green)
          .opacity(goalReached ? 1 : 0)
          .help(goalReached ? Text("Goal reached") : Text(verbatim: ""))
      }
      Text(
        String(
          format: NSLocalizedString("%lld min", comment: "Focus minutes of one day"),
          day.focusMinutes)
      )
      .foregroundColor(.secondary)
      .frame(width: 60, alignment: .trailing)
    }
    .font(.caption)
    .monospacedDigit()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Text(
        StatisticsText.spokenDay(
          StatisticsFormat.spokenDay(day.date, calendar: calendar), pomodoros: day.pomodoros,
          minutes: day.focusMinutes, goalReached: goalReached)))
  }
}

/// Day names in the app's language (which the user can set apart from the system's).
enum StatisticsFormat {
  static var appLocale: Locale {
    Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
  }

  /// Short label such as "Mon 20" / "Th 2, 20".
  static func dayLabel(_ date: Date, calendar: Calendar, locale: Locale = appLocale) -> String {
    format(date, template: "EEEd", calendar: calendar, locale: locale)
  }

  /// Full name for VoiceOver, e.g. "Monday, October 20".
  static func spokenDay(_ date: Date, calendar: Calendar, locale: Locale = appLocale) -> String {
    format(date, template: "EEEEMMMMd", calendar: calendar, locale: locale)
  }

  private static func format(
    _ date: Date, template: String, calendar: Calendar, locale: Locale
  ) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = locale
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
  }
}

/// Saves the CSV where the user picks in a save panel.
enum StatisticsExporter {
  static func defaultFileName(today: Date = Date(), calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: today)
    return String(
      format: "TimeMate-statistics-%04d-%02d-%02d.csv", parts.year ?? 0, parts.month ?? 0,
      parts.day ?? 0)
  }

  static func export(_ csv: String) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = defaultFileName()
    panel.canCreateDirectories = true
    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try Data(csv.utf8).write(to: url, options: .atomic)
    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
    }
  }
}
