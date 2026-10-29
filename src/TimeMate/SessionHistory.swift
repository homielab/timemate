//  Created by homielab.com

import Combine
import Foundation
import os

/// Persistent log of completed Pomodoro sessions, stored as JSON in the app's
/// Application Support folder and kept for `retentionDays` days.
final class SessionHistory: ObservableObject {
  struct Record: Codable, Equatable {
    enum Kind: String, Codable {
      case focus, short, long

      init(_ sessionType: SessionType) {
        switch sessionType {
        case .focus: self = .focus
        case .shortBreak: self = .short
        case .longBreak: self = .long
        }
      }
    }

    /// Effective start: the end minus the session length, so paused time is
    /// not counted as focus time.
    let start: Date
    let end: Date
    let kind: Kind
    let completed: Bool
    /// What the focus session was for; missing in files written before labels.
    var label: String? = nil

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
  }

  struct DayTotals: Equatable {
    let pomodoros: Int
    let focusSeconds: TimeInterval

    var focusMinutes: Int { Int((focusSeconds / 60).rounded()) }
  }

  static let retentionDays = 90

  @Published private(set) var records: [Record] = []
  /// The goal streak of the days trimmed from `records`; saved next to the
  /// history file (see `carryFileURL(for:)`).
  private(set) var goalStreakCarry: GoalStreakCarry?

  /// Where the history is saved; `nil` keeps it in memory only.
  private let fileURL: URL?
  private let now: () -> Date
  let calendar: Calendar
  private var cancellables = Set<AnyCancellable>()
  /// Set when loading skipped unreadable records: the file still holds them,
  /// so it is copied aside before the first save writes it without them.
  private var needsBackupBeforeSave = false

  /// Posted when "today" may have become another day: midnight passed, or the
  /// system time or time zone was changed.
  static let dayChangeNotifications: [Notification.Name] = [
    .NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange,
  ]

  /// The current time as the history sees it (injectable in tests).
  var currentDate: Date { now() }

  init(
    fileURL: URL?,
    now: @escaping () -> Date = { Date() },
    calendar: Calendar = .autoupdatingCurrent,
    notificationCenter: NotificationCenter = .default
  ) {
    self.fileURL = fileURL
    self.now = now
    self.calendar = calendar
    let loaded = Self.load(from: fileURL, now: now())
    goalStreakCarry = Self.loadCarry(from: fileURL.map(Self.carryFileURL(for:)))
    records = trimmed(loaded.records)
    needsBackupBeforeSave = loaded.skippedRecords > 0

    // Views of today's or this week's totals redraw for the new day.
    for name in Self.dayChangeNotifications {
      notificationCenter.publisher(for: name)
        .sink { [weak self] _ in self?.dayMayHaveChanged() }
        .store(in: &cancellables)
    }
  }

  private func dayMayHaveChanged() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.dayMayHaveChanged() }
      return
    }
    objectWillChange.send()
  }

  /// `Application Support/<bundle id>/session-history.json` (inside the app
  /// container when sandboxed).
  static func defaultFileURL(fileManager: FileManager = .default) -> URL? {
    guard
      let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else { return nil }
    let folder = Bundle.main.bundleIdentifier ?? "TimeMate"
    return base.appendingPathComponent(folder, isDirectory: true)
      .appendingPathComponent("session-history.json")
  }

  /// `session-history-streak.json` next to the history file `url`: the goal
  /// streak of trimmed days. Older versions don't write it; it is created on the
  /// first save.
  static func carryFileURL(for url: URL) -> URL {
    url.deletingLastPathComponent()
      .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-streak.json")
  }

  /// Records a completed session that ended at `end` after running `duration`
  /// seconds, with an optional `label` (see `SessionLabel.normalized`).
  func recordCompletedSession(
    _ sessionType: SessionType, duration: TimeInterval, end: Date, label: String? = nil
  ) {
    let record = Record(
      start: end.addingTimeInterval(-max(0, duration)), end: end,
      kind: Record.Kind(sessionType), completed: true, label: SessionLabel.normalized(label))
    records = trimmed(records + [record])
    save()
  }

  /// The labels of the latest focus sessions, newest first, each once (compared
  /// ignoring case, keeping the newest spelling), at most `limit`.
  func recentLabels(limit: Int = 8) -> [String] {
    Self.recentLabels(in: records, limit: limit)
  }

  static func recentLabels(in records: [Record], limit: Int = 8) -> [String] {
    var seen = Set<String>()
    var labels: [String] = []
    for record in records.sorted(by: { $0.end > $1.end }) where record.kind == .focus {
      guard labels.count < limit else { break }
      guard let label = SessionLabel.normalized(record.label) else { continue }
      if seen.insert(label.lowercased()).inserted { labels.append(label) }
    }
    return labels
  }

  /// Deletes all recorded sessions, and the backups of unreadable history
  /// files, which may still hold session labels. A backup that can't be
  /// deleted is logged and doesn't stop the reset.
  func reset() {
    records = []
    goalStreakCarry = nil
    needsBackupBeforeSave = false
    save()
    guard let fileURL else { return }
    for backup in Self.corruptBackups(in: fileURL.deletingLastPathComponent()) {
      do {
        try FileManager.default.removeItem(at: backup)
      } catch {
        Logger.history.error(
          "Could not delete a history backup: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// Completed focus sessions and focus time of the calendar day containing
  /// the current time.
  func todayTotals() -> DayTotals {
    let today = now()
    let focus = records.filter {
      $0.kind == .focus && $0.completed && calendar.isDate($0.end, inSameDayAs: today)
    }
    return DayTotals(
      pomodoros: focus.count, focusSeconds: focus.reduce(0) { $0 + $1.duration })
  }

  // MARK: - Storage

  /// Drops sessions before the start of the cutoff's day, so the CSV export keeps
  /// that day whole and its row matches the streak. First the goal streak up to
  /// that day is carried (from the untrimmed records, which still hold it whole),
  /// unless the carry already covers that day.
  private func trimmed(_ records: [Record]) -> [Record] {
    guard
      let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: now())
    else { return records }
    let cutoffDay = calendar.startOfDay(for: cutoff)
    if goalStreakCarry.map({ $0.throughDay < cutoffDay }) ?? true {
      goalStreakCarry = GoalStreakCarry.advanced(
        goalStreakCarry, through: cutoffDay, records: records, calendar: calendar)
    }
    return records.filter { $0.end >= cutoffDay }
  }

  /// A missing or unreadable carry file means no carry; the streak is then
  /// counted from the kept history only.
  private static func loadCarry(from url: URL?) -> GoalStreakCarry? {
    guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
      return try makeDecoder().decode(GoalStreakCarry.self, from: Data(contentsOf: url))
    } catch {
      Logger.history.error(
        "Could not read the goal streak carry: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  /// Written before the history, so a save cut short never leaves trimmed
  /// history without the carry of its days.
  private func saveCarry(to url: URL) throws {
    let carryURL = Self.carryFileURL(for: url)
    if let goalStreakCarry {
      try Self.makeEncoder().encode(goalStreakCarry).write(to: carryURL, options: .atomic)
    } else if FileManager.default.fileExists(atPath: carryURL.path) {
      try FileManager.default.removeItem(at: carryURL)
    }
  }

  private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  private static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  /// Decodes to `nil` instead of throwing, so one bad element doesn't fail the
  /// whole array.
  private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws {
      value = try? Value(from: decoder)
    }
  }

  /// A missing or empty file starts an empty history. Records that can't be
  /// decoded (an unknown kind, a malformed date) are skipped and the rest are
  /// kept; `skippedRecords` counts them, and the file is copied aside before
  /// the next save writes it without them (see `backUpFile`). A file that isn't
  /// a JSON array at all can't be read and is first moved aside, so the next
  /// save doesn't overwrite the sessions it may still hold.
  private static func load(from url: URL?, now: Date) -> (records: [Record], skippedRecords: Int) {
    guard let url, FileManager.default.fileExists(atPath: url.path) else { return ([], 0) }
    do {
      let data = try Data(contentsOf: url)
      if data.isEmpty { return ([], 0) }
      let decoded = try makeDecoder().decode([Lossy<Record>].self, from: data)
      let records = decoded.compactMap(\.value)
      let skipped = decoded.count - records.count
      if skipped > 0 {
        Logger.history.error(
          "Skipped \(skipped, privacy: .public) unreadable history record(s); the file is backed up before the next save"
        )
      }
      return (records, skipped)
    } catch {
      Logger.history.error(
        "Could not read the session history: \(error.localizedDescription, privacy: .public)")
      backUpFile(at: url, now: now, keepingOriginal: false)
      return ([], 0)
    }
  }

  /// `session-history.corrupt-<yyyyMMdd-HHmmss>.json` next to the history file.
  static func corruptBackupName(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "session-history.corrupt-\(formatter.string(from: date)).json"
  }

  /// The backups of history files in `folder` that were unreadable or held
  /// unreadable records (at most one is kept).
  static func corruptBackups(in folder: URL, fileManager: FileManager = .default) -> [URL] {
    let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
    return names.filter { $0.hasPrefix("session-history.corrupt-") && $0.hasSuffix(".json") }
      .sorted()
      .map { folder.appendingPathComponent($0) }
  }

  /// Moves (or, `keepingOriginal`, copies) the history file to
  /// `corruptBackupName(for: now)`, replacing an older backup so only the
  /// latest one is kept.
  private static func backUpFile(at url: URL, now: Date, keepingOriginal: Bool) {
    let fileManager = FileManager.default
    let folder = url.deletingLastPathComponent()
    for old in corruptBackups(in: folder, fileManager: fileManager) {
      try? fileManager.removeItem(at: old)
    }
    let backup = folder.appendingPathComponent(corruptBackupName(for: now))
    do {
      if keepingOriginal {
        try fileManager.copyItem(at: url, to: backup)
      } else {
        try fileManager.moveItem(at: url, to: backup)
      }
      Logger.history.notice(
        "Backed up the session history to \(backup.lastPathComponent, privacy: .public)")
    } catch {
      Logger.history.error(
        "Could not back up the session history: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func save() {
    guard let fileURL else { return }
    if needsBackupBeforeSave {
      needsBackupBeforeSave = false
      if FileManager.default.fileExists(atPath: fileURL.path) {
        Self.backUpFile(at: fileURL, now: now(), keepingOriginal: true)
      }
    }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try saveCarry(to: fileURL)
      let data = try Self.makeEncoder().encode(records)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      Logger.history.error(
        "Could not save the session history: \(error.localizedDescription, privacy: .public)")
    }
  }
}
