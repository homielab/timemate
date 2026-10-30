//  Created by homielab.com

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StatisticsSection: View {
  @EnvironmentObject var model: PopoverTimerModel
  @AppStorage(SettingsKey.dailyGoal) private var dailyGoal = DailyGoal.off
  @AppStorage(SettingsKey.streakSkipsWeekends) private var streakSkipsWeekends = false
  @AppStorage(SettingsKey.statisticsDays) private var storedDays = SessionStatistics.weekLength
  @State private var showingResetAlert = false
  @State private var showingUndoAlert = false

  private var days: Int { SessionStatistics.sanitizedLength(storedDays) }

  var body: some View {
    SettingsSection(titleKey: "Statistics", systemImage: "chart.bar.fill") {
      DailyGoalRow(goal: $dailyGoal)

      if dailyGoal > DailyGoal.off {
        SettingsToggleRow(titleKey: "Weekends don't break the streak", isOn: $streakSkipsWeekends)
          .help(
            "A Saturday or Sunday that misses the goal is skipped instead of ending the streak.")
      }

      GoalStreakLabel(
        history: model.timer.history, goal: DailyGoal.sanitized(dailyGoal),
        skipWeekends: streakSkipsWeekends)

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

      HourlyFocusView(history: model.timer.history, days: days)

      MenuItemButton(title: "Export CSV…", systemImage: "square.and.arrow.up") {
        StatisticsExporter.export(
          model.timer.history.statisticsCSV(days: days, goal: DailyGoal.sanitized(dailyGoal)),
          fileName: StatisticsExporter.defaultFileName(days: days))
      }

      MenuItemButton(title: "Export all (90 days)…", systemImage: "calendar") {
        StatisticsExporter.export(
          model.timer.history.statisticsCSV(goal: DailyGoal.sanitized(dailyGoal)),
          fileName: StatisticsExporter.defaultFileName(days: nil))
      }
      .help("Saves every kept day of the last 90 days, one row each.")

      MenuItemButton(title: "Export sessions CSV…", systemImage: "list.bullet.rectangle") {
        StatisticsExporter.export(
          model.timer.history.sessionsCSV(), fileName: StatisticsExporter.sessionsFileName())
      }
      .help("Saves every completed session of the last 90 days with its label, one row each.")

      UndoLastSessionButton(
        timer: model.timer, history: model.timer.history, isPresented: $showingUndoAlert)

      MenuItemButton(title: "Reset Statistics", systemImage: "trash") {
        showingResetAlert = true
      }
      .alert("Reset Statistics?", isPresented: $showingResetAlert) {
        Button("Reset", role: .destructive) {
          model.timer.resetStatistics()
        }
        Button("Cancel", role: .cancel) {
        }
      } message: {
        Text("This will delete the history of completed sessions. Are you sure?")
      }
    }
  }
}

/// "Undo Last Session": removes the focus session recorded last after a
/// confirmation naming its label, time and minutes; disabled with none.
private struct UndoLastSessionButton: View {
  let timer: PomodoroTimer
  @ObservedObject var history: SessionHistory
  @Binding var isPresented: Bool
  /// The session the alert names, captured when it opens, so a session
  /// recorded while it is open is neither shown nor deleted.
  @State private var shown: SessionHistory.Record?

  var body: some View {
    MenuItemButton(title: "Undo Last Session", systemImage: "arrow.uturn.backward") {
      shown = history.lastFocusRecord
      isPresented = shown != nil
    }
    .disabled(history.lastFocusRecord == nil)
    .help("Deletes only the focus session recorded last, for one counted by mistake.")
    .alert("Undo Last Session?", isPresented: $isPresented, presenting: shown) { record in
      Button("Delete Session", role: .destructive) {
        timer.undoLastFocusSession(matching: record)
      }
      Button("Cancel", role: .cancel) {
      }
    } message: { record in
      Text(Self.message(for: record))
    }
  }

  static func message(for record: SessionHistory.Record) -> String {
    let label =
      SessionLabel.normalized(record.label)
      ?? Bundle.main.localizedString(forKey: "No label", value: nil, table: nil)
    let formatter = DateIntervalFormatter()
    formatter.locale = AppLocale.current
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return StatisticsText.undoLastSession(
      label: label, timeRange: formatter.string(from: record.start, to: record.end),
      minutes: Int((record.duration / 60).rounded()))
  }
}

/// "Streak: N days" under the goal row, hidden with no goal or no streak; then
/// "Best: N days in the last 90 days" when the record beats the current streak.
private struct GoalStreakLabel: View {
  @ObservedObject var history: SessionHistory
  let goal: Int
  let skipWeekends: Bool

  var body: some View {
    let streak = history.goalStreak(goal: goal, skipWeekends: skipWeekends)
    let best = history.longestGoalStreak(goal: goal, skipWeekends: skipWeekends)
    if streak > 0 {
      Text(StatisticsText.streak(days: streak))
        .font(.caption)
        .foregroundColor(.secondary)
        .monospacedDigit()
    }
    if best > streak {
      Text(StatisticsText.bestStreak(days: best))
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
    .help(
      "Pomodoros to finish each day. TimeMate tells you once when you reach it. A session that runs past midnight counts for the day it ends."
    )
  }
}

/// The last 7 days as one row per day, or the last 30 as a compact bar strip; then
/// the totals, the daily average, the best day and the change against the same
/// number of days before. With a daily goal, days that met it get a check mark
/// (7 days) or a green bar (30 days) and the period shows on how many days it was met.
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
      (days == SessionStatistics.monthLength ? Text("Last 30 days") : Text("Last 7 days"))
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

      if let average = period.dailyAverage {
        Text(StatisticsText.dailyAverage(minutes: average))
          .font(.caption)
          .foregroundColor(.secondary)
          .monospacedDigit()
          .accessibilityLabel(Text(StatisticsText.spokenDailyAverage(minutes: average)))
      }

      if let best = SessionStatistics.bestDay(period.days) {
        Text(
          StatisticsText.bestDay(
            StatisticsFormat.dayLabel(best.date, calendar: history.calendar),
            pomodoros: best.pomodoros, minutes: best.focusMinutes)
        )
        .font(.caption)
        .foregroundColor(.secondary)
        .monospacedDigit()
        .accessibilityLabel(
          Text(
            StatisticsText.spokenBestDay(
              StatisticsFormat.spokenDay(best.date, calendar: history.calendar),
              pomodoros: best.pomodoros, minutes: best.focusMinutes)))
      }

      if period.hasFullPreviousPeriod,
        let percent = SessionStatistics.percentChange(
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
            minutes: total.focusMinutes,
            fraction: SessionStatistics.barFraction(total.focusSeconds, longest: longest))
        }
        if breakdown.otherSeconds > 0 {
          LabelRow(
            name: Text("Other"), spokenName: StatisticsText.localized("Other"),
            minutes: breakdown.otherMinutes,
            fraction: SessionStatistics.barFraction(breakdown.otherSeconds, longest: longest))
        }
        if breakdown.unlabeledSeconds > 0 {
          LabelRow(
            name: Text("No label"), spokenName: StatisticsText.localized("No label"),
            minutes: breakdown.unlabeledMinutes,
            fraction: SessionStatistics.barFraction(breakdown.unlabeledSeconds, longest: longest))
        }
      }
    }
  }
}

/// "By hour": one thin column per hour of the day (0–23) with the focus minutes of
/// the chosen period. Hovering a column shows, and VoiceOver reads, "9 – 10 AM, 25
/// minutes"; the strip as a whole reads "Most focused: 9 – 10 AM". Hidden when empty.
private struct HourlyFocusView: View {
  @ObservedObject var history: SessionHistory
  let days: Int

  private let height: CGFloat = 32

  var body: some View {
    let hours = history.hourlyFocus(days: days)
    if let best = SessionStatistics.mostFocusedHour(hours) {
      let calendar = history.calendar
      let longest = hours[best]
      let summary = StatisticsText.mostFocused(
        StatisticsFormat.hourRange(best, calendar: calendar))
      VStack(alignment: .leading, spacing: 4) {
        Text("By hour")
          .font(.caption)
          .foregroundColor(.secondary)
        HStack(alignment: .bottom, spacing: 1) {
          ForEach(0..<24, id: \.self) { hour in
            let spoken = StatisticsText.spokenLabel(
              StatisticsFormat.hourRange(hour, calendar: calendar),
              minutes: Int((hours[hour] / 60).rounded()))
            RoundedRectangle(cornerRadius: 1)
              .fill(Color.accentColor)
              .opacity(hours[hour] <= 0 ? 0.15 : 0.8)
              .frame(
                maxWidth: .infinity,
                minHeight: 2,
                maxHeight: hours[hour] <= 0
                  ? 2 : max(3, height * CGFloat(hours[hour] / longest))
              )
              .help(Text(spoken))
              .accessibilityElement()
              .accessibilityLabel(Text(spoken))
              .accessibilityHidden(hours[hour] <= 0)
          }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(summary))
        Text(summary)
          .font(.caption)
          .foregroundColor(.secondary)
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
/// goal is green. Hovering a column shows, and VoiceOver reads, the same text
/// (`spokenDays`): the day, its pomodoros and minutes, and whether it met the goal.
struct BarStrip: View {
  let days: [SessionStatistics.Day]
  let maxPomodoros: Int
  let goal: Int
  let calendar: Calendar

  private let height: CGFloat = 40

  /// The tooltip and VoiceOver label of each column, in column order.
  static func spokenDays(
    _ days: [SessionStatistics.Day], goal: Int, calendar: Calendar,
    locale: Locale = StatisticsFormat.appLocale, bundle: Bundle = .main
  ) -> [String] {
    days.map { day in
      StatisticsText.spokenDay(
        StatisticsFormat.spokenDay(day.date, calendar: calendar, locale: locale),
        pomodoros: day.pomodoros, minutes: day.focusMinutes,
        goalReached: DailyGoal.isReached(completed: day.pomodoros, goal: goal),
        bundle: bundle, locale: locale)
    }
  }

  var body: some View {
    let spoken = Self.spokenDays(days, goal: goal, calendar: calendar)
    HStack(alignment: .bottom, spacing: 2) {
      ForEach(Array(days.enumerated()), id: \.element.date) { index, day in
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
          .help(Text(spoken[index]))
          .accessibilityElement()
          .accessibilityLabel(Text(spoken[index]))
      }
    }
    .frame(height: height, alignment: .bottom)
    .accessibilityElement(children: .contain)
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
  static var appLocale: Locale { AppLocale.current }

  /// Short label such as "Mon 20" / "Th 2, 20".
  static func dayLabel(_ date: Date, calendar: Calendar, locale: Locale = appLocale) -> String {
    format(date, template: "EEEd", calendar: calendar, locale: locale)
  }

  /// Full name for VoiceOver, e.g. "Monday, October 20".
  static func spokenDay(_ date: Date, calendar: Calendar, locale: Locale = appLocale) -> String {
    format(date, template: "EEEEMMMMd", calendar: calendar, locale: locale)
  }

  /// One hour of the day as a range, e.g. "9 – 10 AM" / "09:00 – 10:00".
  static func hourRange(_ hour: Int, calendar: Calendar, locale: Locale = appLocale) -> String {
    var components = DateComponents()
    components.year = 2001
    components.month = 1
    components.day = 1
    components.hour = hour
    let start = calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    let formatter = DateIntervalFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = locale
    // "j" alone gives "09 – 10" on a 24-hour clock; minutes make it read as a time.
    let twentyFourHour = [.zeroToTwentyThree, .oneToTwentyFour].contains(locale.hourCycle)
    formatter.dateTemplate = twentyFourHour ? "jm" : "j"
    return formatter.string(from: start, to: start.addingTimeInterval(3600))
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
  /// True while the save panel runs, so closing the popover does not hand the keyboard
  /// back to another app and push the panel behind it.
  private(set) static var isSaving = false

  /// `TimeMate-statistics-<period>-<yyyy-MM-dd>.csv`, the period being `7d`, `30d`… for the
  /// last `days` days or `all` for every kept day (`days` nil).
  static func defaultFileName(
    days: Int?, today: Date = Date(), calendar: Calendar = .current
  ) -> String {
    let period = days.map { "\(max(1, $0))d" } ?? "all"
    return "TimeMate-statistics-\(period)-\(isoDay(today, calendar)).csv"
  }

  static func sessionsFileName(today: Date = Date(), calendar: Calendar = .current) -> String {
    "TimeMate-sessions-\(isoDay(today, calendar)).csv"
  }

  private static func isoDay(_ date: Date, _ calendar: Calendar) -> String {
    SessionStatistics.isoDay(date, timeZone: calendar.timeZone)
  }

  /// The file bytes: a UTF-8 BOM first so Excel reads non-ASCII labels as UTF-8.
  static func data(for csv: String) -> Data {
    Data([0xEF, 0xBB, 0xBF]) + Data(csv.utf8)
  }

  static func export(_ csv: String, fileName: String) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = fileName
    panel.canCreateDirectories = true
    NSApp.activate(ignoringOtherApps: true)
    isSaving = true
    defer { isSaving = false }
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try data(for: csv).write(to: url, options: .atomic)
    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
    }
  }
}
