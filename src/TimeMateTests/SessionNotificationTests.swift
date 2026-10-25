//  Created by homielab.com

import UserNotifications
import XCTest

@testable import TimeMate

final class SessionNotificationTests: XCTestCase {
  private static let suiteName = "TimeMateSessionNotificationTests"

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

  /// Debug builds treat minutes as seconds: focus lasts 3 ticks, short break 2.
  private func makeTimer(autoStart: Bool, keepBreakOpen: Bool = false) -> PomodoroTimer {
    defaults.set(3, forKey: SettingsKey.focusDuration)
    defaults.set(2, forKey: SettingsKey.shortBreakDuration)
    defaults.set(4, forKey: SettingsKey.longBreakDuration)
    defaults.set(4, forKey: SettingsKey.longBreakInterval)
    defaults.set(autoStart, forKey: SettingsKey.autoStartNextSession)
    defaults.set(keepBreakOpen, forKey: SettingsKey.keepBreakScreenOpen)
    defaults.set(false, forKey: SettingsKey.notificationsEnabled)
    defaults.set(0.0, forKey: SettingsKey.alarmVolume)
    return PomodoroTimer(
      defaults: defaults,
      now: { [unowned self] in self.currentTime },
      workspaceNotificationCenter: NotificationCenter(),
      history: SessionHistory(fileURL: nil))
  }

  private func finishSession(_ timer: PomodoroTimer) {
    while timer.state == .active, timer.timeRemaining > 0 {
      let session = timer.currentSessionType
      currentTime = currentTime.addingTimeInterval(1)
      timer.handleTick()
      if timer.currentSessionType != session || timer.isWaitingToContinue { return }
    }
  }

  // MARK: - Content

  func testContentHasNoSoundAndUsesCategoryAndThread() {
    let content = SessionNotification.content(forCompleted: .focus)
    XCTAssertNil(content.sound, "the app plays the alarm itself; a second sound doubles it")
    XCTAssertEqual(content.categoryIdentifier, SessionNotification.categoryIdentifier)
    XCTAssertEqual(content.threadIdentifier, SessionNotification.threadIdentifier)
    XCTAssertEqual(content.title, "TimeMate")
  }

  func testCategoryOffersStartNextAndSkip() {
    let category = SessionNotification.category()
    XCTAssertEqual(category.identifier, SessionNotification.categoryIdentifier)
    XCTAssertEqual(
      category.actions.map(\.identifier),
      [SessionNotificationAction.startNext.rawValue, SessionNotificationAction.skip.rawValue])
  }

  func testUnknownActionIdentifierMapsToNothing() {
    XCTAssertNil(SessionNotificationAction(rawValue: UNNotificationDefaultActionIdentifier))
    XCTAssertNil(SessionNotificationAction(rawValue: UNNotificationDismissActionIdentifier))
  }

  // MARK: - Actions

  func testStartNextStartsTheWaitingSessionWithoutAutoStart() {
    let timer = makeTimer(autoStart: false)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .idle)

    timer.handleNotificationAction(.startNext)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
  }

  func testStartNextLeavesAnAutoStartedSessionRunning() {
    let timer = makeTimer(autoStart: true)
    timer.startTimer()
    finishSession(timer)
    let remaining = timer.timeRemaining

    timer.handleNotificationAction(.startNext)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
    XCTAssertEqual(timer.timeRemaining, remaining)
  }

  func testStartNextContinuesPastTheBreakScreen() {
    let timer = makeTimer(autoStart: false, keepBreakOpen: true)
    timer.startTimer()
    finishSession(timer)
    timer.handleNotificationAction(.startNext)
    finishSession(timer)
    XCTAssertTrue(timer.isWaitingToContinue)

    timer.handleNotificationAction(.startNext)
    XCTAssertFalse(timer.isWaitingToContinue)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .active)
  }

  func testSkipMovesToTheSessionAfterTheNextOne() {
    let timer = makeTimer(autoStart: true)
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)

    timer.handleNotificationAction(.skip)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.focusSessionsCompleted, 1)
  }
}
