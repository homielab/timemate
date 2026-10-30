//  Created by homielab.com

import Combine
import XCTest

@testable import TimeMate

final class BreakOverlayModelTests: XCTestCase {
  private static let suiteName = "TimeMateBreakOverlayTests"

  private var defaults: UserDefaults!
  private var currentTime = Date(timeIntervalSince1970: 1_000_000)
  private var timer: PomodoroTimer!
  private var model: BreakOverlayModel!
  private var cancellables = Set<AnyCancellable>()
  private var modelChanges = 0
  private var countdownChanges = 0

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
    defaults.set(30, forKey: SettingsKey.focusDuration)
    defaults.set(10, forKey: SettingsKey.shortBreakDuration)
    defaults.set(5, forKey: SettingsKey.overlaySkipDelay)
    defaults.set(true, forKey: SettingsKey.autoStartNextSession)
    defaults.set(false, forKey: SettingsKey.notificationsEnabled)
    defaults.set(0.0, forKey: SettingsKey.alarmVolume)

    timer = PomodoroTimer(
      defaults: defaults,
      now: { [weak self] in self?.currentTime ?? Date(timeIntervalSince1970: 0) },
      workspaceNotificationCenter: NotificationCenter(),
      history: SessionHistory(fileURL: nil),
      playSound: { _, _ in }, isFullscreenProbe: { false })

    model = BreakOverlayModel(
      timer: timer, defaults: defaults,
      now: { [weak self] in self?.currentTime ?? Date(timeIntervalSince1970: 0) })

    model.objectWillChange.sink { [weak self] _ in self?.modelChanges += 1 }
      .store(in: &cancellables)
    model.countdown.objectWillChange.sink { [weak self] _ in self?.countdownChanges += 1 }
      .store(in: &cancellables)
  }

  override func tearDown() {
    cancellables.removeAll()
    model = nil
    timer = nil
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  private func runTicks(_ count: Int) {
    for _ in 0..<count {
      currentTime = currentTime.addingTimeInterval(1)
      timer.handleTick()
    }
  }

  func testOverlayRedrawsOnlyCountdownOnTicks() {
    timer.startTimer()
    timer.skipSession()
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)

    model.setLive(true)
    modelChanges = 0
    countdownChanges = 0

    runTicks(5)

    XCTAssertEqual(
      modelChanges, 0, "slow-changing overlay state must not fire objectWillChange on ticks")
    XCTAssertGreaterThan(countdownChanges, 0, "countdown text must update on ticks")
    XCTAssertEqual(model.countdown.timeRemaining, timer.timeRemaining)
  }

  func testClosedOverlayDoesNotChangeOnTicks() {
    timer.startTimer()
    timer.skipSession()

    model.setLive(false)
    modelChanges = 0
    countdownChanges = 0

    runTicks(5)

    XCTAssertEqual(modelChanges, 0)
    XCTAssertEqual(countdownChanges, 0)
  }

  func testModelUpdatesOnSessionAndStateChange() {
    timer.startTimer()
    XCTAssertEqual(model.state, .active)
    XCTAssertEqual(model.currentSessionType, .focus)

    timer.pauseTimer()
    XCTAssertEqual(model.state, .paused)

    timer.skipSession()
    XCTAssertEqual(model.currentSessionType, .shortBreak)
  }

  func testWallClockRunsOnlyWhileTheTimerIsNotActive() {
    timer.startTimer()
    timer.skipSession()
    model.setLive(true)
    XCTAssertEqual(timer.state, .active)
    XCTAssertFalse(model.countdown.isClockRunning, "an active timer already ticks every second")

    timer.pauseTimer()
    XCTAssertEqual(timer.state, .paused)
    XCTAssertTrue(model.countdown.isClockRunning)
    XCTAssertEqual(model.countdown.clockInterval, 1)

    timer.startTimer()
    XCTAssertEqual(timer.state, .active)
    XCTAssertFalse(model.countdown.isClockRunning)

    model.setLive(false)
    XCTAssertFalse(model.countdown.isClockRunning)
  }

  func testWallClockRunsWhileWaitingOnTheBreakScreen() {
    timer.startTimer()
    timer.skipSession()
    model.setLive(true)
    runTicks(timer.timeRemaining)

    XCTAssertTrue(timer.isWaitingToContinue)
    XCTAssertEqual(timer.state, .idle)
    XCTAssertTrue(model.countdown.isClockRunning)
    XCTAssertEqual(model.countdown.clockInterval, 60, "nobody needs seconds while waiting")

    model.setLive(false)
    XCTAssertNil(model.countdown.clockInterval)
    XCTAssertFalse(model.countdown.isClockRunning)
  }

  func testSkipCountdownTicksWithBreak() {
    timer.startTimer()
    timer.skipSession()

    model.setLive(true)
    XCTAssertEqual(model.countdown.skipSecondsRemaining, 5)
    XCTAssertFalse(model.countdown.canSkip)

    runTicks(3)
    XCTAssertEqual(model.countdown.skipSecondsRemaining, 2)
    XCTAssertFalse(model.countdown.canSkip)

    runTicks(2)
    XCTAssertEqual(model.countdown.skipSecondsRemaining, 0)
    XCTAssertTrue(model.countdown.canSkip)
  }

  func testExtendingTheBreakDoesNotShortenTheSkipDelay() {
    timer.startTimer()
    timer.skipSession()
    model.beginBreakScreen()

    for _ in 0..<5 {
      model.extendBreak()
    }
    XCTAssertEqual(model.countdown.skipSecondsRemaining, 5)
    XCTAssertFalse(model.countdown.canSkip)

    runTicks(5)
    XCTAssertEqual(model.countdown.skipSecondsRemaining, 0)
    XCTAssertTrue(model.countdown.canSkip)
  }

  func testGoingLiveAgainKeepsTheSkipCountdown() {
    timer.startTimer()
    timer.skipSession()
    model.beginBreakScreen()
    runTicks(3)
    XCTAssertEqual(model.countdown.skipSecondsRemaining, 2)

    model.setLive(false)
    model.setLive(true)
    model.setLive(true)
    XCTAssertEqual(model.countdown.skipSecondsRemaining, 2)
    XCTAssertTrue(model.countdown.isLive)

    runTicks(1)
    XCTAssertEqual(model.countdown.skipSecondsRemaining, 1)
  }

  func testNewBreakScreenStartsTheSkipDelayOver() {
    timer.startTimer()
    timer.skipSession()
    model.beginBreakScreen()
    runTicks(3)
    XCTAssertEqual(model.countdown.skipSecondsRemaining, 2)

    model.setLive(false)
    model.beginBreakScreen()
    XCTAssertEqual(model.countdown.skipSecondsRemaining, 5)
    XCTAssertTrue(model.countdown.isLive)
  }

  func testTipStaysUntilTheNextBreakScreen() {
    var picks = 0
    let model = BreakOverlayModel(
      timer: timer, defaults: defaults,
      tip: {
        picks += 1
        return "tip \(picks)"
      })
    let primary = BreakOverlayView(model: model, isPrimary: true)
    let secondary = BreakOverlayView(model: model, isPrimary: false)
    XCTAssertEqual(primary.model.tip, "tip 1")
    XCTAssertEqual(secondary.model.tip, primary.model.tip)

    model.setLive(true)
    model.setLive(false)
    XCTAssertEqual(model.tip, "tip 1", "going live again keeps the tip")

    model.chooseTip()
    XCTAssertEqual(model.tip, "tip 2")
    XCTAssertEqual(secondary.model.tip, "tip 2")
  }
}

final class BreakOverlayModelTodayTests: XCTestCase {
  private static let suiteName = "TimeMateBreakOverlayTodayTests"
  private var defaults: UserDefaults!
  private var history: SessionHistory!
  private var model: BreakOverlayModel!

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
    history = SessionHistory(fileURL: nil)
    let timer = PomodoroTimer(
      defaults: defaults, workspaceNotificationCenter: NotificationCenter(), history: history,
      playSound: { _, _ in }, isFullscreenProbe: { false })
    model = BreakOverlayModel(timer: timer, defaults: defaults, tip: { "tip" })
  }

  override func tearDown() {
    model = nil
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  private func recordPomodoros(_ count: Int) {
    for _ in 0..<count {
      history.recordCompletedSession(.focus, duration: 1500, end: Date())
    }
  }

  func testNoPomodoroTodayHidesTheLine() {
    defaults.set(8, forKey: SettingsKey.dailyGoal)
    model.refreshToday()
    XCTAssertNil(model.today)
  }

  func testShowsGoalProgressAndVoiceOverLabel() throws {
    defaults.set(8, forKey: SettingsKey.dailyGoal)
    recordPomodoros(3)
    model.refreshToday()
    let today = try XCTUnwrap(model.today)
    let expected = TodaySummary(
      pomodoros: 3, minutes: 75, goal: 8, streak: { history.goalStreak(goal: 8) })
    XCTAssertEqual(today, expected)
    XCTAssertTrue(today.visibleText.contains("3/8"))
    XCTAssertEqual(today.accessibilityLabel, expected.accessibilityLabel)
    XCTAssertEqual(BreakOverlayModel.todayText(today), today.visibleText)
  }

  func testWithoutGoalShowsOnlyPomodoros() throws {
    recordPomodoros(3)
    model.refreshToday()
    let today = try XCTUnwrap(model.today)
    XCTAssertFalse(today.hasGoal)
    XCTAssertFalse(today.visibleText.contains("/"))
    XCTAssertEqual(BreakOverlayModel.todayText(today), today.visibleText)
  }

  func testStreakIsAppendedToTheLine() {
    let summary = TodaySummary(pomodoros: 3, minutes: 75, goal: 8, streak: { 5 })
    XCTAssertEqual(
      BreakOverlayModel.todayText(summary), "\(summary.visibleText) · \(summary.streakText)")
  }
}
