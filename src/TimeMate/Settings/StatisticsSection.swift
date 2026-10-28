//  Created by homielab.com

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StatisticsSection: View {
  @EnvironmentObject var model: PopoverTimerModel
  @AppStorage(SettingsKey.dailyGoal) private var dailyGoal = DailyGoal.off
  @AppStorage(SettingsKey.statisticsDays) private var storedDays = SessionStatistics.weekLength
  @State private var showingResetAlert = false

  private var days: Int { SessionStatistics.sanitizedLength(storedDays) }

  var body: some View {
    SettingsSection(titleKey: "Statistics", systemImage: "chart.bar.fill") {
      DailyGoalRow(goal: $dailyGoal)

      GoalStreakLabel(history: model.timer.history, goal: DailyGoal.sanitized(dailyGoal))

      Picker(selection: $storedDays) {
        Text("7 days").tag(SessionStatistics.weekLength)
        Text("30 days").tag(SessionStatistics.monthLength)
      } label: {
        Text("Statistics period")
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .accessibilityLabel(Text("Statistics period"))

      PeriodStatisticsView(
        history: model.timer.history, days: days, goal: DailyGoal.sanitized(dailyGoal))

      LabelTotalsView(history: model.timer.history, days: days)

      MenuItemButton(title: "Export CSV…", systemImage: "square.and.arrow.up") {
        StatisticsExporter.export(
          model.timer.history.statisticsCSV(days: days, goal: DailyGoal.sanitized(dailyGoal)))
      }

      MenuItemButton(title: "Export sessions CSV…", systemImage: "list.bullet.rectangle") {
        StatisticsExporter.export(
          model.timer.history.sessionsCSV(), fileName: StatisticsExporter.sessionsFileName())
      }
      .help("Saves every completed session of the last 90 days with its label, one row each.")

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

/// "Streak: N days" under the goal row; hidden with no goal or no streak.
private struct GoalStreakLabel: View {
  @ObservedObject var history: SessionHistory
  let goal: Int

  var body: some View {
    let streak = history.goalStreak(goal: goal)
    if streak > 0 {
      Text(StatisticsText.streak(days: streak))
        .font(.caption)
        .foregroundColor(.secondary)
        .monospacedDigit()
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

/// The last 7 days as one row per day, or the last 30 as a compact bar strip; then
/// the totals and the change against the same number of days before. With a daily
/// goal, days that met it get a check mark (7 days) or a green bar (30 days) and
/// the period shows on how many days it was met.
private struct PeriodStatisticsView: View {
  @ObservedObject var history: SessionHistory
  let days: Int
  let goal: Int

  var body: some View {
    let period = history.statistics(days: days)
    let maxPomodoros = max(1, period.days.map(\.pomodoros).max() ?? 0)
    let totals = period.totals
    let previous = period.previousTotals

    VStack(alignment: .leading, spacing: 4) {
      Text(days == SessionStatistics.monthLength ? "Last 30 days" : "Last 7 days")
        .font(.caption)
        .foregroundColor(.secondary)

      if days == SessionStatistics.monthLength {
        BarStrip(
          days: period.days, maxPomodoros: maxPomodoros, goal: goal, calendar: history.calendar)
      } else {
        ForEach(period.days, id: \.date) { day in
          DayRow(
            day: day, fraction: Double(day.pomodoros) / Double(maxPomodoros), goal: goal,
            calendar: history.calendar)
        }
      }

      Divider().padding(.vertical, 2)

      Text(
        StatisticsText.total(
          pomodoros: totals.pomodoros, minutes: totals.focusMinutes, days: days)
      )
      .font(.callout.weight(.semibold))
      .monospacedDigit()

      if let percent = SessionStatistics.percentChange(
        current: totals.pomodoros, previous: previous.pomodoros)
      {
        Text(
          StatisticsText.change(
            pomodoros: totals.pomodoros - previous.pomodoros, percent: percent,
            minutes: totals.focusMinutes - previous.focusMinutes, days: days)
        )
        .font(.caption)
        .foregroundColor(.secondary)
        .monospacedDigit()
      }

      if goal > DailyGoal.off {
        Text(
          StatisticsText.goalDays(
            reached: SessionStatistics.daysReachingGoal(period.days, goal: goal),
            of: period.days.count)
        )
        .font(.caption)
        .foregroundColor(.secondary)
        .monospacedDigit()
      }
    }
  }
}

/// "By label": focus time per label over the chosen period, the five longest, then
/// "Other" and "No label". Hidden when the period has no completed focus session.
/// Each row is one VoiceOver element: "name, X minutes".
private struct LabelTotalsView: View {
  @ObservedObject var history: SessionHistory
  let days: Int

  var body: some View {
    let totals = history.labelTotals(days: days)
    if !totals.isEmpty {
      let breakdown = SessionStatistics.labelBreakdown(totals)
      let longest = max(1, totals.map(\.focusSeconds).max() ?? 0)
      VStack(alignment: .leading, spacing: 4) {
        Text("By label")
          .font(.caption)
          .foregroundColor(.secondary)
        ForEach(breakdown.top, id: \.label) { total in
          LabelRow(
            name: Text(verbatim: total.label ?? ""), spokenName: total.label ?? "",
            minutes: total.focusMinutes, fraction: total.focusSeconds / longest)
        }
        if breakdown.otherSeconds > 0 {
          LabelRow(
            name: Text("Other"), spokenName: StatisticsText.localized("Other"),
            minutes: breakdown.otherMinutes, fraction: breakdown.otherSeconds / longest)
        }
        if breakdown.unlabeledSeconds > 0 {
          LabelRow(
            name: Text("No label"), spokenName: StatisticsText.localized("No label"),
            minutes: breakdown.unlabeledMinutes, fraction: breakdown.unlabeledSeconds / longest)
        }
      }
    }
  }
}

private struct LabelRow: View {
  let name: Text
  let spokenName: String
  let minutes: Int
  let fraction: Double

  var body: some View {
    HStack(spacing: 8) {
      name
        .frame(width: 90, alignment: .leading)
        .lineLimit(1)
        .truncationMode(.tail)

      GeometryReader { proxy in
        RoundedRectangle(cornerRadius: 2)
          .fill(Color.accentColor.opacity(fraction <= 0 ? 0 : 0.8))
          .frame(width: max(0, proxy.size.width * fraction))
      }
      .frame(height: 8)

      Text(
        String(
          format: NSLocalizedString("%lld min", comment: "Focus minutes of one day"), minutes)
      )
      .foregroundColor(.secondary)
      .frame(width: 60, alignment: .trailing)
    }
    .font(.caption)
    .monospacedDigit()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(StatisticsText.spokenLabel(spokenName, minutes: minutes)))
  }
}

/// One thin column per day, oldest first, today last; a day that met the daily
/// goal is green. Hovering a column names the day. VoiceOver reads the totals
/// below instead of 30 separate columns.
private struct BarStrip: View {
  let days: [SessionStatistics.Day]
  let maxPomodoros: Int
  let goal: Int
  let calendar: Calendar

  private let height: CGFloat = 40

  var body: some View {
    HStack(alignment: .bottom, spacing: 2) {
      ForEach(days, id: \.date) { day in
        let reached = DailyGoal.isReached(completed: day.pomodoros, goal: goal)
        RoundedRectangle(cornerRadius: 1.5)
          .fill(reached ? Color.green : Color.accentColor)
          .opacity(day.pomodoros == 0 ? 0.15 : 0.8)
          .frame(
            maxWidth: .infinity,
            minHeight: day.pomodoros == 0 ? 2 : 3,
            maxHeight: day.pomodoros == 0
              ? 2 : max(3, height * CGFloat(day.pomodoros) / CGFloat(maxPomodoros))
          )
          .help(
            Text(
              verbatim:
                "\(StatisticsFormat.dayLabel(day.date, calendar: calendar)): \(day.pomodoros)"))
      }
    }
    .frame(height: height, alignment: .bottom)
    .accessibilityHidden(true)
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

  static func sessionsFileName(today: Date = Date(), calendar: Calendar = .current) -> String {
    defaultFileName(today: today, calendar: calendar)
      .replacingOccurrences(of: "statistics", with: "sessions")
  }

  /// The file bytes: a UTF-8 BOM first so Excel reads non-ASCII labels as UTF-8.
  static func data(for csv: String) -> Data {
    Data([0xEF, 0xBB, 0xBF]) + Data(csv.utf8)
  }

  static func export(_ csv: String, fileName: String = defaultFileName()) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = fileName
    panel.canCreateDirectories = true
    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try data(for: csv).write(to: url, options: .atomic)
    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
    }
  }
}
