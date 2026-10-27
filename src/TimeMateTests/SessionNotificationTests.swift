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
    let content = SessionNotification.content(
      forCompleted: .focus, next: .shortBreak, minutes: 5, autoStarted: false)
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

  func testAutoStartedCategoryHasOnlySkip() {
    let category = SessionNotification.autoStartedCategory()
    XCTAssertEqual(category.actions.map(\.identifier), [SessionNotificationAction.skip.rawValue])
    XCTAssertEqual(
      Set(SessionNotification.categories().map(\.identifier)),
      [SessionNotification.categoryIdentifier, SessionNotification.autoStartedCategoryIdentifier])
  }

  // MARK: - What comes next

  private func content(
    _ completed: SessionType, next: SessionType, minutes: Int, autoStarted: Bool
  ) -> UNMutableNotificationContent {
    SessionNotification.content(
      forCompleted: completed, next: next, minutes: minutes, autoStarted: autoStarted)
  }

  func testFocusIntoShortBreakWaiting() {
    let c = content(.focus, next: .shortBreak, minutes: 5, autoStarted: false)
    XCTAssertEqual(c.body, "Next: Short Break · 5 min")
    XCTAssertEqual(c.categoryIdentifier, SessionNotification.categoryIdentifier)
  }

  func testFocusIntoLongBreakWaiting() {
    let c = content(.focus, next: .longBreak, minutes: 15, autoStarted: false)
    XCTAssertEqual(c.body, "Next: Long Break · 15 min")
    XCTAssertEqual(c.categoryIdentifier, SessionNotification.categoryIdentifier)
  }

  func testBreakIntoFocusWaiting() {
    let c = content(.shortBreak, next: .focus, minutes: 25, autoStarted: false)
    XCTAssertEqual(c.body, "Next: Focus · 25 min")
    XCTAssertEqual(c.categoryIdentifier, SessionNotification.categoryIdentifier)
  }

  func testAutoStartedSaysSoAndDropsStartNext() {
    let c = content(.focus, next: .shortBreak, minutes: 5, autoStarted: true)
    XCTAssertEqual(c.body, "Short Break started · 5 min")
    XCTAssertEqual(c.categoryIdentifier, SessionNotification.autoStartedCategoryIdentifier)
  }

  func testTimerPostsTheNextSessionFollowingItsSettings() {
    var posted: [UNNotificationRequest] = []
    defaults.set(3, forKey: SettingsKey.focusDuration)
    defaults.set(7, forKey: SettingsKey.shortBreakDuration)
    defaults.set(true, forKey: SettingsKey.autoStartNextSession)
    defaults.set(0.0, forKey: SettingsKey.alarmVolume)
    let timer = PomodoroTimer(
      defaults: defaults,
      now: { [unowned self] in self.currentTime },
      workspaceNotificationCenter: NotificationCenter(),
      history: SessionHistory(fileURL: nil),
      notificationCenter: NotificationCenter(),
      postNotification: { posted.append($0) })
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(posted.first?.content.body, "Short Break started · 7 min")
    XCTAssertEqual(
      posted.first?.content.categoryIdentifier, SessionNotification.autoStartedCategoryIdentifier)
  }

  func testBreaksAutoStartButFocusWaits() {
    var posted: [UNNotificationRequest] = []
    defaults.set(3, forKey: SettingsKey.focusDuration)
    defaults.set(2, forKey: SettingsKey.shortBreakDuration)
    defaults.set(true, forKey: SettingsKey.autoStartBreaks)
    defaults.set(false, forKey: SettingsKey.autoStartFocus)
    defaults.set(false, forKey: SettingsKey.keepBreakScreenOpen)
    defaults.set(0.0, forKey: SettingsKey.alarmVolume)
    let timer = PomodoroTimer(
      defaults: defaults,
      now: { [unowned self] in self.currentTime },
      workspaceNotificationCenter: NotificationCenter(),
      history: SessionHistory(fileURL: nil),
      notificationCenter: NotificationCenter(),
      postNotification: { posted.append($0) })
    timer.startTimer()
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
    finishSession(timer)
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(timer.state, .idle)
    XCTAssertEqual(posted.count, 2)
    XCTAssertEqual(
      posted[0].content.categoryIdentifier, SessionNotification.autoStartedCategoryIdentifier)
    // The focus session waits, so the end-of-break notification keeps "Start Next".
    XCTAssertEqual(posted[1].content.categoryIdentifier, SessionNotification.categoryIdentifier)
  }

  func testUnknownActionIdentifierMapsToNothing() {
    XCTAssertNil(SessionNotificationAction(rawValue: UNNotificationDefaultActionIdentifier))
    XCTAssertNil(SessionNotificationAction(rawValue: UNNotificationDismissActionIdentifier))
  }

  func testResponseMapsButtonsToTimerActions() {
    XCTAssertEqual(
      NotificationResponse(actionIdentifier: SessionNotificationAction.startNext.rawValue),
      .timerAction(.startNext))
    XCTAssertEqual(
      NotificationResponse(actionIdentifier: SessionNotificationAction.skip.rawValue),
      .timerAction(.skip))
  }

  func testClickingTheBannerBodyOpensThePopover() {
    XCTAssertEqual(
      NotificationResponse(actionIdentifier: UNNotificationDefaultActionIdentifier), .openPopover)
  }

  func testDismissAndUnknownResponsesAreIgnored() {
    XCTAssertEqual(
      NotificationResponse(actionIdentifier: UNNotificationDismissActionIdentifier), .ignore)
    XCTAssertEqual(NotificationResponse(actionIdentifier: "something.else"), .ignore)
  }

  // MARK: - Focus modes

  func testContentIsTimeSensitiveWhenBreakingThroughFocus() {
    XCTAssertEqual(
      SessionNotification.content(
        forCompleted: .focus, next: .shortBreak, minutes: 5, autoStarted: false,
        breakThroughFocus: true
      ).interruptionLevel, .timeSensitive)
    XCTAssertEqual(
      SessionNotification.content(
        forCompleted: .focus, next: .shortBreak, minutes: 5, autoStarted: false,
        breakThroughFocus: false
      ).interruptionLevel, .active)
  }

  func testRequestShowsRightAway() {
    let request = SessionNotification.request(
      forCompleted: .shortBreak, next: .focus, minutes: 25, autoStarted: false,
      breakThroughFocus: true, identifier: "id")
    XCTAssertEqual(request.identifier, "id")
    XCTAssertNil(request.trigger)
    XCTAssertEqual(request.content.categoryIdentifier, SessionNotification.categoryIdentifier)
  }

  private func postedRequests(breakThroughFocus: Bool?, notificationsEnabled: Bool = true)
    -> [UNNotificationRequest]
  {
    var posted: [UNNotificationRequest] = []
    defaults.set(3, forKey: SettingsKey.focusDuration)
    defaults.set(false, forKey: SettingsKey.autoStartNextSession)
    defaults.set(notificationsEnabled, forKey: SettingsKey.notificationsEnabled)
    defaults.set(0.0, forKey: SettingsKey.alarmVolume)
    if let breakThroughFocus {
      defaults.set(breakThroughFocus, forKey: SettingsKey.breakThroughFocus)
    }
    let timer = PomodoroTimer(
      defaults: defaults,
      now: { [unowned self] in self.currentTime },
      workspaceNotificationCenter: NotificationCenter(),
      history: SessionHistory(fileURL: nil),
      notificationCenter: NotificationCenter(),
      postNotification: { posted.append($0) })
    timer.startTimer()
    finishSession(timer)
    return posted
  }

  func testTimerPostsATimeSensitiveNotificationByDefault() {
    let posted = postedRequests(breakThroughFocus: nil)
    XCTAssertEqual(posted.count, 1)
    XCTAssertEqual(posted.first?.content.interruptionLevel, .timeSensitive)
  }

  func testTimerFollowsTheBreakThroughFocusSetting() {
    XCTAssertEqual(
      postedRequests(breakThroughFocus: false).first?.content.interruptionLevel, .active)
  }

  func testTimerPostsNothingWithNotificationsOff() {
    XCTAssertTrue(postedRequests(breakThroughFocus: true, notificationsEnabled: false).isEmpty)
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
