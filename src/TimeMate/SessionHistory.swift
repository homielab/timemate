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

  /// Where the history is saved; `nil` keeps it in memory only.
  private let fileURL: URL?
  private let now: () -> Date
  let calendar: Calendar
  private var cancellables = Set<AnyCancellable>()

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
    records = trimmed(Self.load(from: fileURL, now: now()))

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

  /// Deletes all recorded sessions.
  func reset() {
    records = []
    save()
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

  private func trimmed(_ records: [Record]) -> [Record] {
    guard
      let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: now())
    else { return records }
    return records.filter { $0.end >= cutoff }
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

  /// A missing or empty file starts an empty history. A file that can't be
  /// read is first moved aside (see `backUpUnreadableFile`), so the next save
  /// doesn't overwrite the sessions it may still hold.
  private static func load(from url: URL?, now: Date) -> [Record] {
    guard let url, FileManager.default.fileExists(atPath: url.path) else { return [] }
    do {
      let data = try Data(contentsOf: url)
      if data.isEmpty { return [] }
      return try makeDecoder().decode([Record].self, from: data)
    } catch {
      Logger.history.error(
        "Could not read the session history: \(error.localizedDescription, privacy: .public)")
      backUpUnreadableFile(at: url, now: now)
      return []
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

  /// The backups of unreadable history files in `folder` (at most one is kept).
  static func corruptBackups(in folder: URL, fileManager: FileManager = .default) -> [URL] {
    let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
    return names.filter { $0.hasPrefix("session-history.corrupt-") && $0.hasSuffix(".json") }
      .sorted()
      .map { folder.appendingPathComponent($0) }
  }

  /// Renames the unreadable file to `corruptBackupName(for: now)`, replacing an
  /// older backup so only the latest one is kept.
  private static func backUpUnreadableFile(at url: URL, now: Date) {
    let fileManager = FileManager.default
    let folder = url.deletingLastPathComponent()
    for old in corruptBackups(in: folder, fileManager: fileManager) {
      try? fileManager.removeItem(at: old)
    }
    let backup = folder.appendingPathComponent(corruptBackupName(for: now))
    do {
      try fileManager.moveItem(at: url, to: backup)
      Logger.history.notice(
        "Moved the unreadable session history to \(backup.lastPathComponent, privacy: .public)")
    } catch {
      Logger.history.error(
        "Could not back up the session history: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func save() {
    guard let fileURL else { return }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let data = try Self.makeEncoder().encode(records)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      Logger.history.error(
        "Could not save the session history: \(error.localizedDescription, privacy: .public)")
    }
  }
}
