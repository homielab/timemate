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
      history: SessionHistory(fileURL: nil))

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
}
