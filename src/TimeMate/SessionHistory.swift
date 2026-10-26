//  Created by homielab.com

import Combine
import Foundation

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
    records = trimmed(Self.load(from: fileURL))

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
  /// seconds.
  func recordCompletedSession(_ sessionType: SessionType, duration: TimeInterval, end: Date) {
    let record = Record(
      start: end.addingTimeInterval(-max(0, duration)), end: end,
      kind: Record.Kind(sessionType), completed: true)
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

  /// A missing or unreadable file starts an empty history.
  private static func load(from url: URL?) -> [Record] {
    guard let url, let data = try? Data(contentsOf: url) else { return [] }
    return (try? makeDecoder().decode([Record].self, from: data)) ?? []
  }

  private func save() {
    guard let fileURL else { return }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let data = try Self.makeEncoder().encode(records)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      #if DEBUG
        print("TimeMate: could not save session history: \(error)")
      #endif
    }
  }
}
