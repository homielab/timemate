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

  // MARK: - Recent labels

  func testRecentLabelsDedupeIgnoringCaseKeepingNewestSpelling() {
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(5), label: "write report")
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(4), label: "Email")
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(1), label: "Write Report")
    XCTAssertEqual(history.recentLabels(), ["Write Report", "Email"])
  }

  func testRecentLabelsNewestFirstEvenWhenRecordedOutOfOrder() {
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(1), label: "B")
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(3), label: "A")
    XCTAssertEqual(history.recentLabels(), ["B", "A"])
  }

  func testRecentLabelsLimit() {
    let history = makeHistory()
    for index in 0..<5 {
      history.recordCompletedSession(
        .focus, duration: 1500, end: hoursAgo(Double(10 - index)), label: "L\(index)")
    }
    XCTAssertEqual(history.recentLabels(limit: 3), ["L4", "L3", "L2"])
    XCTAssertEqual(history.recentLabels().count, 5)
  }

  func testRecentLabelsSkipBreaksAndMissingLabels() {
    let history = makeHistory()
    history.recordCompletedSession(.shortBreak, duration: 300, end: hoursAgo(1), label: "Break")
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(2), label: nil)
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(3), label: "  ")
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(4), label: "Code")
    XCTAssertEqual(history.recentLabels(), ["Code"])
  }

  func testRecentLabelsEmptyHistory() {
    XCTAssertEqual(makeHistory().recentLabels(), [])
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
    XCTAssertEqual(Set(json[0].keys), ["start", "end", "kind", "completed", "seconds"])
    XCTAssertEqual(json[0]["seconds"] as? Double, 300)
    XCTAssertEqual(json[0]["kind"] as? String, "short")
    XCTAssertEqual(json[0]["completed"] as? Bool, true)
  }

  func testLabelIsSavedAndReadBack() throws {
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 1500, end: currentTime, label: " Report ")
    history.recordCompletedSession(.focus, duration: 1500, end: currentTime, label: "  ")

    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [[String: Any]])
    XCTAssertEqual(json[0]["label"] as? String, "Report")
    XCTAssertNil(json[1]["label"], "no label is left out of the file")
    XCTAssertEqual(makeHistory().records.map(\.label), ["Report", nil])
  }

  func testFileWithoutLabelsStillLoads() throws {
    let old = """
      [
        {"completed": true, "end": "2026-03-10T14:00:00Z", "kind": "focus",
         "start": "2026-03-10T13:35:00Z"},
        {"completed": true, "end": "2026-03-10T14:05:00Z", "kind": "short",
         "start": "2026-03-10T14:00:00Z"}
      ]
      """
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(old.utf8).write(to: fileURL)

    let records = makeHistory().records
    XCTAssertEqual(records.map(\.kind), [.focus, .short])
    XCTAssertEqual(records.map(\.label), [nil, nil])
    XCTAssertEqual(records.first?.duration, 1500)
    XCTAssertEqual(SessionHistory.corruptBackups(in: fileURL.deletingLastPathComponent()), [])
  }

  func testUnreadableRecordIsSkippedAndTheRestKept() throws {
    let mixed = """
      [
        {"completed": true, "end": "2026-03-10T14:00:00Z", "kind": "focus",
         "start": "2026-03-10T13:35:00Z"},
        {"completed": true, "end": "2026-03-10T14:30:00Z", "kind": "deep",
         "start": "2026-03-10T14:05:00Z"},
        {"completed": true, "end": "not a date", "kind": "short",
         "start": "2026-03-10T14:00:00Z"},
        {"completed": true, "end": "2026-03-10T14:10:00Z", "kind": "long",
         "start": "2026-03-10T14:00:00Z"}
      ]
      """
    let folder = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(mixed.utf8).write(to: fileURL)

    let history = makeHistory()
    XCTAssertEqual(history.records.map(\.kind), [.focus, .long])
    XCTAssertEqual(SessionHistory.corruptBackups(in: folder), [])
    XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

    // The next save writes the file without the skipped records, after
    // copying the original aside.
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(1))
    XCTAssertEqual(makeHistory().records.map(\.kind), [.focus, .long, .focus])
    let backups = SessionHistory.corruptBackups(in: folder)
    XCTAssertEqual(backups.count, 1)
    XCTAssertEqual(try Data(contentsOf: backups[0]), Data(mixed.utf8))
  }

  func testUnknownKindIsBackedUpBeforeTheFirstSave() throws {
    let mixed = """
      [
        {"completed": true, "end": "2026-03-10T14:00:00Z", "kind": "focus",
         "start": "2026-03-10T13:35:00Z"},
        {"completed": true, "end": "2026-03-10T14:30:00Z", "kind": "x",
         "start": "2026-03-10T14:05:00Z"},
        {"completed": true, "end": "2026-03-10T14:40:00Z", "kind": "short",
         "start": "2026-03-10T14:35:00Z"}
      ]
      """
    let folder = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(mixed.utf8).write(to: fileURL)

    let history = makeHistory()
    XCTAssertEqual(history.records.count, 2)
    XCTAssertEqual(SessionHistory.corruptBackups(in: folder), [], "loading alone backs up nothing")

    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(1))

    let backups = SessionHistory.corruptBackups(in: folder)
    XCTAssertEqual(
      backups.map(\.lastPathComponent), [SessionHistory.corruptBackupName(for: currentTime)])
    let backup = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: backups[0])) as? [[String: Any]])
    XCTAssertEqual(backup.map { $0["kind"] as? String }, ["focus", "x", "short"])
    let main = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [[String: Any]])
    XCTAssertEqual(main.count, 3)

    // Only the first save backs up; the next one leaves the backup alone.
    currentTime = currentTime.addingTimeInterval(60)
    history.recordCompletedSession(.focus, duration: 1500, end: currentTime)
    XCTAssertEqual(SessionHistory.corruptBackups(in: folder), backups)
    XCTAssertEqual(try Data(contentsOf: backups[0]), Data(mixed.utf8))
  }

  func testResetDeletesTheBackupOfUnreadableRecords() throws {
    let mixed = """
      [
        {"completed": true, "end": "2026-03-10T14:30:00Z", "kind": "x",
         "start": "2026-03-10T14:05:00Z", "label": "Private"}
      ]
      """
    let folder = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(mixed.utf8).write(to: fileURL)
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(1))
    XCTAssertEqual(SessionHistory.corruptBackups(in: folder).count, 1, "save backs up the file")

    history.reset()

    XCTAssertEqual(SessionHistory.corruptBackups(in: folder), [])
    XCTAssertEqual(makeHistory().records, [])
  }

  func testResetDeletesTheBackupOfAnUnreadableFile() throws {
    let folder = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: fileURL)
    let history = makeHistory()
    XCTAssertEqual(SessionHistory.corruptBackups(in: folder).count, 1)

    history.reset()

    XCTAssertEqual(SessionHistory.corruptBackups(in: folder), [])
    XCTAssertEqual(makeHistory().records, [])
  }

  func testReadableFileIsNotBackedUpOnSave() throws {
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(2))
    let reloaded = makeHistory()
    reloaded.recordCompletedSession(.focus, duration: 1500, end: hoursAgo(1))

    XCTAssertEqual(makeHistory().records.count, 2)
    XCTAssertEqual(SessionHistory.corruptBackups(in: fileURL.deletingLastPathComponent()), [])
  }

  func testNonArrayJSONIsMovedAside() throws {
    let folder = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("{\"records\": []}".utf8).write(to: fileURL)

    XCTAssertEqual(makeHistory().records, [])
    XCTAssertEqual(SessionHistory.corruptBackups(in: folder).count, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
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

  func testRecordingKeepsTheWholeDayOfTheCutoff() {
    let history = makeHistory()
    // The cutoff is 2025-12-10 15:00: both sessions of that day are kept, so the
    // day's CSV row counts them; the evening before it is dropped.
    let morningOfTheCutoffDay = daysAgo(90).addingTimeInterval(-6 * 3600)
    let eveningBefore = daysAgo(91).addingTimeInterval(8 * 3600)
    history.recordCompletedSession(.focus, duration: 1500, end: morningOfTheCutoffDay)
    history.recordCompletedSession(.focus, duration: 1500, end: eveningBefore)

    XCTAssertEqual(history.records.map(\.end), [morningOfTheCutoffDay])
    XCTAssertEqual(makeHistory().records.map(\.end), [morningOfTheCutoffDay])
  }

  func testLoadingTrimsSessionsThatAgedOut() {
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 60, end: daysAgo(80))
    history.recordCompletedSession(.focus, duration: 60, end: daysAgo(10))

    currentTime = daysAgo(-20)  // 20 days later: the first one is now 100 days old
    XCTAssertEqual(makeHistory().records.count, 1)
  }

  // MARK: - Goal streak carry

  private var carryURL: URL { SessionHistory.carryFileURL(for: fileURL) }

  /// A history file as an older version wrote it (no carry file), with one focus
  /// session per day from `days` days ago up to yesterday.
  private func writeOldFile(days: Int) throws {
    let records = (1...days).reversed().map { offset in
      SessionHistory.Record(
        start: daysAgo(offset).addingTimeInterval(-1500), end: daysAgo(offset), kind: .focus,
        completed: true)
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(records).write(to: fileURL)
  }

  func testCarryFileSitsNextToTheHistory() {
    XCTAssertEqual(carryURL.lastPathComponent, "session-history-streak.json")
    XCTAssertEqual(carryURL.deletingLastPathComponent(), fileURL.deletingLastPathComponent())
  }

  func testOlderFileLoadsAndKeepsTheStreakOfItsTrimmedDays() throws {
    try writeOldFile(days: 100)
    let history = makeHistory()
    XCTAssertEqual(history.records.count, SessionHistory.retentionDays)
    XCTAssertEqual(history.goalStreak(goal: 1), 100)
    XCTAssertFalse(FileManager.default.fileExists(atPath: carryURL.path))

    history.recordCompletedSession(.focus, duration: 1500, end: currentTime)
    XCTAssertTrue(FileManager.default.fileExists(atPath: carryURL.path))
    XCTAssertEqual(history.goalStreak(goal: 1), 101)
    XCTAssertEqual(makeHistory().goalStreak(goal: 1), 101)
  }

  func testCarryKeepsCountingOnLaterDays() throws {
    try writeOldFile(days: 100)
    makeHistory().recordCompletedSession(.focus, duration: 1500, end: currentTime)
    for _ in 1...5 {
      currentTime = daysAgo(-1)
      makeHistory().recordCompletedSession(.focus, duration: 1500, end: currentTime)
    }
    XCTAssertEqual(makeHistory().goalStreak(goal: 1), 106)
    currentTime = daysAgo(-2)  // two days without a session break the streak
    XCTAssertEqual(makeHistory().goalStreak(goal: 1), 0)
  }

  func testUnreadableCarryFileIsCountedAgainFromTheHistory() throws {
    try writeOldFile(days: 100)
    try FileManager.default.createDirectory(
      at: carryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: carryURL)
    let history = makeHistory()
    XCTAssertEqual(history.goalStreak(goal: 1), 100)
    history.recordCompletedSession(.focus, duration: 1500, end: currentTime)
    XCTAssertEqual(makeHistory().goalStreak(goal: 1), 101)
  }

  func testResetRemovesTheCarry() throws {
    try writeOldFile(days: 100)
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 1500, end: currentTime)
    history.reset()
    XCTAssertFalse(FileManager.default.fileExists(atPath: carryURL.path))
    XCTAssertEqual(history.goalStreak(goal: 1), 0)
    XCTAssertEqual(makeHistory().goalStreak(goal: 1), 0)
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

  // MARK: - Sessions CSV

  func testSessionsCSVWithoutSessionsIsOnlyTheHeader() {
    XCTAssertEqual(makeHistory().sessionsCSV(), "start,end,kind,minutes,label\r\n")
  }

  func testSessionsCSVRowsKindsAndEmptyLabel() {
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 25 * 60, end: hoursAgo(2))
    history.recordCompletedSession(.shortBreak, duration: 5 * 60, end: hoursAgo(1))
    history.recordCompletedSession(.longBreak, duration: 15 * 60, end: currentTime)
    let lines = history.sessionsCSV().components(separatedBy: "\r\n")
    XCTAssertEqual(
      lines,
      [
        "start,end,kind,minutes,label",
        "2026-03-10T12:35:00Z,2026-03-10T13:00:00Z,focus,25,",
        "2026-03-10T13:55:00Z,2026-03-10T14:00:00Z,short_break,5,",
        "2026-03-10T14:45:00Z,2026-03-10T15:00:00Z,long_break,15,",
        "",
      ])
  }

  func testSessionsCSVQuotesCommasQuotesAndNewlines() {
    let history = makeHistory()
    history.recordCompletedSession(.focus, duration: 60, end: hoursAgo(3), label: "a, b")
    history.recordCompletedSession(.focus, duration: 60, end: hoursAgo(2), label: "say \"hi\"")
    let rows = history.sessionsCSV().components(separatedBy: "\r\n")
    XCTAssertTrue(rows[1].hasSuffix(",1,\"a, b\""))
    XCTAssertTrue(rows[2].hasSuffix(",1,\"say \"\"hi\"\"\""))
    XCTAssertEqual(SessionHistory.csvField(label: "x\ny"), "\"x\ny\"")
  }

  func testSessionsCSVNeutralisesFormulaLabels() {
    XCTAssertEqual(SessionHistory.csvField(label: "=SUM(A1)"), "'=SUM(A1)")
    XCTAssertEqual(SessionHistory.csvField(label: "+1"), "'+1")
    XCTAssertEqual(SessionHistory.csvField(label: "-1"), "'-1")
    XCTAssertEqual(SessionHistory.csvField(label: "@cmd"), "'@cmd")
    XCTAssertEqual(SessionHistory.csvField(label: "=a,b"), "\"'=a,b\"")
    XCTAssertEqual(SessionHistory.csvField(label: "plain = ok"), "plain = ok")
    XCTAssertEqual(SessionHistory.csvField(label: nil), "")
  }
}
