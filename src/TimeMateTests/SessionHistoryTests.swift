//  Created by homielab.com

import XCTest

@testable import TimeMate

final class SessionHistoryTests: XCTestCase {
  private var directory: URL!
  private var fileURL: URL!
  private var currentTime: Date!
  private var calendar: Calendar!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SessionHistoryTests-\(UUID().uuidString)", isDirectory: true)
    fileURL = directory.appendingPathComponent("nested/session-history.json")
    calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    // 2026-03-10 15:00:00 UTC
    currentTime = Date(timeIntervalSince1970: 1_773_154_800)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  // MARK: - Helpers

  private func makeHistory(fileURL: URL? = nil) -> SessionHistory {
    SessionHistory(
      fileURL: fileURL ?? self.fileURL,
      now: { [weak self] in self?.currentTime ?? Date(timeIntervalSince1970: 0) },
      calendar: calendar)
  }

  private func hoursAgo(_ hours: Double) -> Date {
    currentTime.addingTimeInterval(-hours * 3600)
  }

  private func daysAgo(_ days: Int) -> Date {
    calendar.date(byAdding: .day, value: -days, to: currentTime)!
  }

  // MARK: - Write / read

  func testRecordsArePersistedAndReadBack() throws {
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(2))
    history.recordCompletedSession(.shortBreak, duration: 300, end: hoursAgo(1.9))
    history.recordCompletedSession(.longBreak, duration: 900, end: hoursAgo(1))

    XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    let reloaded = makeHistory()
    XCTAssertEqual(reloaded.records, history.records)
    XCTAssertEqual(reloaded.records.map(\.kind), [.focus, .short, .long])
    XCTAssertEqual(reloaded.records.first?.start, hoursAgo(2).addingTimeInterval(-1500))
    XCTAssertTrue(reloaded.records.allSatisfy(\.completed))
  }

  func testFileUsesDocumentedJSONShape() throws {
    let history = makeHistory()
    history.recordCompletedSession(.shortBreak, duration: 300, end: currentTime)

    let data = try Data(contentsOf: fileURL)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    XCTAssertEqual(json.count, 1)
    XCTAssertEqual(Set(json[0].keys), ["start", "end", "kind", "completed"])
    XCTAssertEqual(json[0]["kind"] as? String, "short")
    XCTAssertEqual(json[0]["completed"] as? Bool, true)
  }

  func testMissingOrEmptyFileStartsEmpty() throws {
    XCTAssertEqual(makeHistory().records, [])

    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: fileURL)
    XCTAssertEqual(makeHistory().records, [])
    XCTAssertEqual(SessionHistory.corruptBackups(in: fileURL.deletingLastPathComponent()), [])
  }

  func testCorruptFileIsMovedAsideInsteadOfOverwritten() throws {
    let folder = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let garbage = Data("not json {".utf8)
    try garbage.write(to: fileURL)

    let history = makeHistory()
    XCTAssertEqual(history.records, [])
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    let backups = SessionHistory.corruptBackups(in: folder)
    XCTAssertEqual(
      backups.map(\.lastPathComponent), [SessionHistory.corruptBackupName(for: currentTime)])
    XCTAssertEqual(try Data(contentsOf: backups[0]), garbage)

    // New sessions go to a fresh file; the backup is left alone.
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(1))
    XCTAssertEqual(makeHistory().records.count, 1)
    XCTAssertEqual(try Data(contentsOf: backups[0]), garbage)
  }

  func testOnlyTheLatestCorruptBackupIsKept() throws {
    let folder = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("first".utf8).write(to: fileURL)
    _ = makeHistory()

    currentTime = currentTime.addingTimeInterval(3600)
    try Data("second".utf8).write(to: fileURL)
    _ = makeHistory()

    let backups = SessionHistory.corruptBackups(in: folder)
    XCTAssertEqual(
      backups.map(\.lastPathComponent), [SessionHistory.corruptBackupName(for: currentTime)])
    XCTAssertEqual(try Data(contentsOf: backups[0]), Data("second".utf8))
  }

  func testCorruptBackupNameUsesTheDate() {
    let name = SessionHistory.corruptBackupName(for: currentTime)
    XCTAssertTrue(name.hasPrefix("session-history.corrupt-2026"), name)
    XCTAssertTrue(name.hasSuffix(".json"), name)
    XCTAssertEqual(name.count, "session-history.corrupt-yyyyMMdd-HHmmss.json".count)
  }

  func testInMemoryHistoryWritesNothing() {
    let history = SessionHistory(fileURL: nil, now: { self.currentTime }, calendar: calendar)
    history.recordCompletedSession(.focus, duration: 60, end: currentTime)
    XCTAssertEqual(history.records.count, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
  }

  func testResetClearsMemoryAndFile() {
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 1500, end: currentTime)
    history.reset()

    XCTAssertEqual(history.records, [])
    XCTAssertEqual(history.todayTotals(), SessionHistory.DayTotals(pomodoros: 0, focusSeconds: 0))
    XCTAssertEqual(makeHistory().records, [])
  }

  // MARK: - Today's totals

  func testTodayTotalsCountOnlyTodaysFocusSessions() {
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(3))
    history.recordCompletedSession(.shortBreak, duration: 300, end: hoursAgo(2.9))
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(2))
    history.recordCompletedSession(.longBreak, duration: 900, end: hoursAgo(1))
    // 2026-03-09 23:50 UTC: yesterday.
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(15 + 1.0 / 6))

    let totals = history.todayTotals()
    XCTAssertEqual(totals.pomodoros, 2)
    XCTAssertEqual(totals.focusMinutes, 50)
  }

  func testTodayTotalsFollowTheClockPastMidnight() {
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 60, end: currentTime)
    history.recordCompletedSession(.focus, duration: 60, end: currentTime)
    XCTAssertEqual(history.todayTotals(), SessionHistory.DayTotals(pomodoros: 2, focusSeconds: 120))
    XCTAssertEqual(history.todayTotals().focusMinutes, 2)

    currentTime = currentTime.addingTimeInterval(10 * 3600)  // 01:00 next day
    XCTAssertEqual(history.todayTotals().pomodoros, 0)
    XCTAssertEqual(history.records.count, 2)
  }

  // MARK: - 90-day retention

  func testRecordingTrimsSessionsOlderThan90Days() {
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 60, end: daysAgo(120))
    history.recordCompletedSession(.focus, duration: 60, end: daysAgo(91))
    history.recordCompletedSession(.focus, duration: 60, end: daysAgo(89))
    history.recordCompletedSession(.focus, duration: 60, end: currentTime)

    XCTAssertEqual(history.records.map(\.end), [daysAgo(89), currentTime])
    XCTAssertEqual(makeHistory().records.count, 2)
  }

  func testLoadingTrimsSessionsThatAgedOut() {
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 60, end: daysAgo(80))
    history.recordCompletedSession(.focus, duration: 60, end: daysAgo(10))

    currentTime = daysAgo(-20)  // 20 days later: the first one is now 100 days old
    XCTAssertEqual(makeHistory().records.count, 1)
  }

  // MARK: - Day changes

  func testTodayRedrawsAndResetsWhenTheDayChanges() {
    let center = NotificationCenter()
    let history = SessionHistory(
      fileURL: nil,
      now: { [weak self] in self?.currentTime ?? Date(timeIntervalSince1970: 0) },
      calendar: calendar, notificationCenter: center)
    history.recordCompletedSession(.focus, duration: 1500, end: currentTime)
    XCTAssertEqual(history.todayTotals().pomodoros, 1)

    var redraws = 0
    let cancellable = history.objectWillChange.sink { redraws += 1 }
    // 2026-03-11 00:00:30 UTC
    currentTime = Date(timeIntervalSince1970: 1_773_187_230)
    for name in SessionHistory.dayChangeNotifications {
      center.post(name: name, object: nil)
    }
    XCTAssertEqual(redraws, 3)
    XCTAssertEqual(
      history.todayTotals(), SessionHistory.DayTotals(pomodoros: 0, focusSeconds: 0))
    cancellable.cancel()
  }
}
