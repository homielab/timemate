//  Created by homielab.com

import Combine
import XCTest

@testable import TimeMate

/// The popover re-renders a view only when an object it observes changes, so
/// counting `objectWillChange` per tick measures its redraws.
final class PopoverTimerModelTests: XCTestCase {
  private static let suiteName = "TimeMatePopoverTests"

  private var defaults: UserDefaults!
  private var currentTime = Date(timeIntervalSince1970: 1_000_000)
  private var timer: PomodoroTimer!
  private var model: PopoverTimerModel!
  private var cancellables = Set<AnyCancellable>()
  private var modelChanges = 0
  private var countdownChanges = 0

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
    defaults.set(30, forKey: SettingsKey.focusDuration)
    defaults.set(5, forKey: SettingsKey.shortBreakDuration)
    defaults.set(false, forKey: SettingsKey.notificationsEnabled)
    defaults.set(0.0, forKey: SettingsKey.alarmVolume)
    timer = PomodoroTimer(
      defaults: defaults,
      now: { [weak self] in self?.currentTime ?? Date(timeIntervalSince1970: 0) },
      workspaceNotificationCenter: NotificationCenter(),
      history: SessionHistory(fileURL: nil), playSound: { _, _ in }, isFullscreenProbe: { false })
    model = PopoverTimerModel(timer: timer)
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

  func testClosedPopoverDoesNotChangeOnTicks() {
    timer.startTimer()
    modelChanges = 0
    countdownChanges = 0
    runTicks(10)
    XCTAssertEqual(modelChanges, 0)
    XCTAssertEqual(countdownChanges, 0)
  }

  func testOpenPopoverRedrawsOnlyTheCountdownOnTicks() {
    timer.startTimer()
    model.setPopoverVisible(true)
    modelChanges = 0
    countdownChanges = 0
    runTicks(10)
    XCTAssertEqual(modelChanges, 0, "the rest of the popover must not redraw each second")
    XCTAssertGreaterThan(countdownChanges, 0)
    XCTAssertEqual(model.countdown.timeRemaining, timer.timeRemaining)
  }

  func testOpeningCatchesUpWithTheTimer() {
    timer.startTimer()
    runTicks(7)
    XCTAssertEqual(model.countdown.timeRemaining, 30)
    model.setPopoverVisible(true)
    XCTAssertEqual(model.countdown.timeRemaining, 23)
    XCTAssertEqual(model.countdown.progress, timer.progress, accuracy: 0.0001)
  }

  func testClosingStopsFollowingTheTimer() {
    timer.startTimer()
    model.setPopoverVisible(true)
    model.setPopoverVisible(false)
    XCTAssertFalse(model.countdown.isLive)
    runTicks(3)
    XCTAssertEqual(model.countdown.timeRemaining, 30)
  }

  func testSessionChangesReachTheModelWhileClosed() {
    timer.startTimer()
    runTicks(30)
    XCTAssertEqual(model.currentSessionType, .shortBreak)
    XCTAssertEqual(model.focusSessionsCompleted, 1)
    XCTAssertEqual(model.state, timer.state)
  }
}
