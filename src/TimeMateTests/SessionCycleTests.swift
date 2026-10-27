//  Created by homielab.com

import XCTest

@testable import TimeMate

final class SessionCycleTests: XCTestCase {
  private static let suiteName = "TimeMateSessionCycleTests"

  private var defaults: UserDefaults!
  private var currentTime = Date(timeIntervalSince1970: 1_000_000)

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
  }

  override func tearDown() {
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  // MARK: - Interval

  func testIntervalIsClampedToOneThroughEight() {
    XCTAssertEqual(SessionCycle.sanitizedInterval(nil), 4)
    XCTAssertEqual(SessionCycle.sanitizedInterval(0), 1)
    XCTAssertEqual(SessionCycle.sanitizedInterval(-3), 1)
    XCTAssertEqual(SessionCycle.sanitizedInterval(1), 1)
    XCTAssertEqual(SessionCycle.sanitizedInterval(5), 5)
    XCTAssertEqual(SessionCycle.sanitizedInterval(8), 8)
    XCTAssertEqual(SessionCycle.sanitizedInterval(1000), 8)
  }

  /// Debug builds treat minutes as seconds.
  private func makeTimer(interval: Int) -> PomodoroTimer {
    defaults.set(1, forKey: SettingsKey.focusDuration)
    defaults.set(1, forKey: SettingsKey.shortBreakDuration)
    defaults.set(1, forKey: SettingsKey.longBreakDuration)
    defaults.set(interval, forKey: SettingsKey.longBreakInterval)
    defaults.set(true, forKey: SettingsKey.autoStartNextSession)
    defaults.set(false, forKey: SettingsKey.keepBreakScreenOpen)
    defaults.set(false, forKey: SettingsKey.notificationsEnabled)
    defaults.set(0.0, forKey: SettingsKey.alarmVolume)
    return PomodoroTimer(
      defaults: defaults,
      now: { [unowned self] in self.currentTime },
      workspaceNotificationCenter: NotificationCenter(),
      history: SessionHistory(fileURL: nil),
      notificationCenter: NotificationCenter())
  }

  /// Runs focus sessions until a long break starts; returns how many it took.
  private func focusSessionsBeforeLongBreak(_ timer: PomodoroTimer) -> Int {
    timer.startTimer()
    var focusCount = 0
    for _ in 0..<40 {
      let session = timer.currentSessionType
      currentTime = currentTime.addingTimeInterval(1)
      timer.handleTick()
      if session == .focus, timer.currentSessionType != .focus { focusCount += 1 }
      if timer.currentSessionType == .longBreak { return focusCount }
    }
    return -1
  }

  func testZeroIntervalInDefaultsGivesALongBreakAfterEveryFocus() {
    XCTAssertEqual(focusSessionsBeforeLongBreak(makeTimer(interval: 0)), 1)
  }

  func testHugeIntervalInDefaultsIsCappedAtEight() {
    XCTAssertEqual(focusSessionsBeforeLongBreak(makeTimer(interval: 99)), 8)
  }

  // MARK: - VoiceOver

  func testCycleLabelCountsDoneSessions() {
    XCTAssertEqual(
      SessionCycle.accessibilityLabel(completed: 2, total: 4, isLongBreak: false),
      "2 of 4 focus sessions done")
    XCTAssertEqual(
      SessionCycle.accessibilityLabel(completed: 0, total: 6, isLongBreak: false),
      "0 of 6 focus sessions done")
  }

  func testCycleLabelStaysInRange() {
    XCTAssertEqual(
      SessionCycle.accessibilityLabel(completed: 9, total: 4, isLongBreak: false),
      "4 of 4 focus sessions done")
    XCTAssertEqual(
      SessionCycle.accessibilityLabel(completed: -1, total: 0, isLongBreak: false),
      "0 of 1 focus sessions done")
  }

  func testCycleLabelNamesTheLongBreak() {
    XCTAssertEqual(
      SessionCycle.accessibilityLabel(completed: 0, total: 4, isLongBreak: true), "Long Break")
  }

  func testClockSpeechIsSpelledOutWithFixedLabel() {
    let ring = SessionCycle.clockAccessibility(secondsRemaining: 1500, progress: 0.75)
    XCTAssertEqual(ring.label, "Time remaining")
    XCTAssertTrue(ring.value.contains("25 minutes"), ring.value)
    XCTAssertFalse(ring.value.contains(":"), ring.value)
    XCTAssertTrue(ring.value.hasSuffix("75% remaining"), ring.value)

    let plain = SessionCycle.clockAccessibility(secondsRemaining: 45, progress: nil)
    XCTAssertEqual(plain.label, ring.label)
    XCTAssertTrue(plain.value.contains("45"), plain.value)
    XCTAssertFalse(plain.value.contains("%"), plain.value)
  }

  func testProgressValueIsPercentRemaining() {
    XCTAssertEqual(SessionCycle.progressAccessibilityValue(0.75), "75% remaining")
    XCTAssertEqual(SessionCycle.progressAccessibilityValue(1), "100% remaining")
    XCTAssertEqual(SessionCycle.progressAccessibilityValue(0.004), "0% remaining")
    XCTAssertEqual(SessionCycle.progressAccessibilityValue(1.5), "100% remaining")
  }
}
