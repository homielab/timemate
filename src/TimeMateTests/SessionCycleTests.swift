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
      notificationCenter: NotificationCenter(), isFullscreenProbe: { false })
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

  func testSettingsShowsTheIntervalTheTimerRuns() {
    XCTAssertEqual(SessionCycle.displayInterval(12), 8)
    XCTAssertEqual(SessionCycle.displayInterval(0), 1)
    XCTAssertEqual(SessionCycle.displayInterval(-2), 1)
    XCTAssertEqual(SessionCycle.displayInterval(4), 4)
  }

  // MARK: - VoiceOver

  func testCyclesStepperValueNamesFocusSessions() {
    XCTAssertEqual(SessionCycle.settingsAccessibilityValue(4), "4 focus sessions")
  }

  func testCyclesStepperValueUsesPluralsInEnglishAndVietnamese() throws {
    let bundle = Bundle(for: PomodoroTimer.self)
    for (localization, one, four, hint) in [
      ("en", "1 focus session", "4 focus sessions", "Long break after this many focus sessions"),
      ("vi", "1 phiên tập trung", "4 phiên tập trung", "Nghỉ dài sau số phiên tập trung này"),
    ] {
      let path = try XCTUnwrap(bundle.path(forResource: localization, ofType: "lproj"))
      let localized = try XCTUnwrap(Bundle(path: path))
      let format = localized.localizedString(
        forKey: "%lld focus sessions", value: nil, table: nil)
      let locale = Locale(identifier: localization)
      XCTAssertEqual(String(format: format, locale: locale, 1), one)
      XCTAssertEqual(String(format: format, locale: locale, 4), four)
      XCTAssertEqual(
        localized.localizedString(
          forKey: "Long break after this many focus sessions", value: nil, table: nil),
        hint)
    }
  }

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

  // MARK: - Stale cycle

  private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  /// 2026-03-10 at `hour`:`minute` UTC.
  private func march10(_ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: hour, minute: minute))!
  }

  func testCycleIsFreshUpToFourHoursOnTheSameDay() {
    let last = march10(9)
    XCTAssertFalse(SessionCycle.isStale(lastActivity: last, now: last, calendar: utc))
    XCTAssertFalse(SessionCycle.isStale(lastActivity: last, now: march10(13), calendar: utc))
    XCTAssertTrue(
      SessionCycle.isStale(
        lastActivity: last, now: march10(13).addingTimeInterval(1), calendar: utc))
  }

  func testCycleIsStaleAfterMoreThanFourHoursOnTheSameDay() {
    XCTAssertTrue(
      SessionCycle.isStale(lastActivity: march10(9), now: march10(14), calendar: utc))
  }

  func testShortGapAcrossMidnightKeepsTheCycle() {
    let lateNight = march10(23, 50)
    let afterMidnight = lateNight.addingTimeInterval(20 * 60)
    XCTAssertFalse(SessionCycle.isStale(lastActivity: lateNight, now: afterMidnight, calendar: utc))
    XCTAssertFalse(
      SessionCycle.isStale(
        lastActivity: march10(23, 30), now: march10(23, 30).addingTimeInterval(3600),
        calendar: utc))
  }

  func testCycleIsStaleOnTheNextDayAfterMoreThanAnHour() {
    let lateNight = march10(23)
    XCTAssertTrue(
      SessionCycle.isStale(
        lastActivity: lateNight, now: lateNight.addingTimeInterval(9 * 3600), calendar: utc))
    XCTAssertTrue(
      SessionCycle.isStale(
        lastActivity: march10(23, 30), now: march10(23, 30).addingTimeInterval(3601),
        calendar: utc))
  }

  func testSameDayGapOverAnHourKeepsTheCycle() {
    XCTAssertFalse(
      SessionCycle.isStale(lastActivity: march10(9), now: march10(11), calendar: utc))
  }

  func testCalendarDayFollowsTheCalendarsTimeZone() {
    // 16:30 and 18:00 UTC are 23:30 and 01:00 in Ho Chi Minh City (UTC+7):
    // a 90 minute gap across midnight there, on the same day in UTC.
    var saigon = utc
    saigon.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    let last = march10(16, 30)
    let now = march10(18)
    XCTAssertTrue(SessionCycle.isStale(lastActivity: last, now: now, calendar: saigon))
    XCTAssertFalse(SessionCycle.isStale(lastActivity: last, now: now, calendar: utc))
  }

  func testOnlyAStalePauseRestartsTheCycle() {
    XCTAssertFalse(
      SessionCycle.pauseRestartsCycle(pausedAt: march10(9), now: march10(10), calendar: utc))
    XCTAssertTrue(
      SessionCycle.pauseRestartsCycle(pausedAt: march10(9), now: march10(14), calendar: utc))
    XCTAssertFalse(SessionCycle.pauseRestartsCycle(pausedAt: nil, now: march10(9), calendar: utc))
  }

  func testUnknownLastActivityIsStale() {
    XCTAssertTrue(SessionCycle.isStale(lastActivity: nil, now: march10(9), calendar: utc))
  }

  func testClockSetBackDoesNotMakeTheCycleStale() {
    XCTAssertFalse(
      SessionCycle.isStale(lastActivity: march10(12), now: march10(11), calendar: utc))
  }
}
