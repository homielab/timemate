//  Created by homielab.com

import AppKit
import Combine
import XCTest

@testable import TimeMate

/// The menu bar view re-renders only when the object it observes changes, so
/// counting `objectWillChange` per tick measures its redraws.
final class MenuBarModelTests: XCTestCase {
  private static let suiteName = "TimeMateMenuBarTests"

  private var defaults: UserDefaults!
  private var currentTime = Date(timeIntervalSince1970: 1_000_000)
  private var timer: PomodoroTimer!
  private var model: MenuBarModel!
  private var cancellables = Set<AnyCancellable>()
  private var modelChanges = 0
  private var timerChanges = 0

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
      history: SessionHistory(fileURL: nil))
    model = MenuBarModel(timer: timer)
    model.objectWillChange.sink { [weak self] _ in self?.modelChanges += 1 }
      .store(in: &cancellables)
    timer.objectWillChange.sink { [weak self] _ in self?.timerChanges += 1 }
      .store(in: &cancellables)
  }

  override func tearDown() {
    cancellables.removeAll()
    model = nil
    timer = nil
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  private func tick(after seconds: TimeInterval = 1) {
    currentTime = currentTime.addingTimeInterval(seconds)
    timer.handleTick()
  }

  private func resetCounts() {
    modelChanges = 0
    timerChanges = 0
  }

  func testATickChangesTheMenuBarOnce() {
    timer.startTimer()
    resetCounts()
    tick()
    // Before: the view observed the timer, which announces timeRemaining and progress.
    XCTAssertEqual(timerChanges, 2)
    XCTAssertEqual(modelChanges, 1)
    XCTAssertEqual(model.timeRemaining, timer.timeRemaining)
  }

  func testTenTicksChangeTheMenuBarTenTimes() {
    timer.startTimer()
    resetCounts()
    for _ in 0..<10 { tick() }
    XCTAssertEqual(timerChanges, 20)
    XCTAssertEqual(modelChanges, 10)
    XCTAssertEqual(model.timeRemaining, 20)
  }

  func testATickWithTheSameSecondDoesNotChangeTheMenuBar() {
    timer.startTimer()
    tick()
    resetCounts()
    // 0.3 s later the rounded remaining time is still the same.
    tick(after: 0.3)
    XCTAssertEqual(timerChanges, 2)
    XCTAssertEqual(modelChanges, 0)
  }

  func testATickWhileIdleDoesNotChangeTheMenuBar() {
    resetCounts()
    tick()
    XCTAssertEqual(modelChanges, 0)
  }

  func testFollowsStateAndSessionChanges() {
    timer.startTimer()
    XCTAssertEqual(model.state, .active)
    timer.pauseTimer()
    XCTAssertEqual(model.state, .paused)
    timer.skipSession()
    XCTAssertEqual(model.currentSessionType, timer.currentSessionType)
    XCTAssertEqual(model.timeRemaining, timer.timeRemaining)
    XCTAssertEqual(model.state, timer.state)
  }

  func testAccessibilityLabelMatchesTheTimer() {
    timer.startTimer()
    for _ in 0..<5 { tick() }
    let expected = StatusItemMenu.accessibilityLabel(
      sessionType: timer.currentSessionType, state: timer.state,
      secondsRemaining: timer.timeRemaining, isBreakPostponed: timer.isBreakPostponed,
      isWaitingToContinue: timer.isWaitingToContinue)
    XCTAssertEqual(model.accessibilityLabel, expected)
  }

  func testStatusItemLabelFollowsTheModelWithVoiceOver() {
    let statusItem = NSStatusBar.system.statusItem(withLength: 90)
    defer { NSStatusBar.system.removeStatusItem(statusItem) }
    let controller = StatusItemController(
      timer: timer, menuBarStyle: .minutesSeconds, statusItem: statusItem)
    // Let the controller read the real VoiceOver state first, then pretend it's on.
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    controller.setAccessibilityLabelUpdates(enabled: true)
    timer.startTimer()
    tick()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    XCTAssertEqual(
      statusItem.button?.accessibilityLabel(), controller.menuBarModel.accessibilityLabel)
    XCTAssertEqual(controller.menuBarModel.timeRemaining, 29)
  }

  func testStatusItemLabelFollowsTheModelWithVoiceOverInMinutesOnlyStyle() {
    let statusItem = NSStatusBar.system.statusItem(withLength: 90)
    defer { NSStatusBar.system.removeStatusItem(statusItem) }
    let controller = StatusItemController(
      timer: timer, menuBarStyle: .minutesOnly, statusItem: statusItem)
    // Let the controller read the real VoiceOver state first, then pretend it's on.
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    controller.setAccessibilityLabelUpdates(enabled: true)
    timer.startTimer()
    tick()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    XCTAssertEqual(
      statusItem.button?.accessibilityLabel(), controller.menuBarModel.accessibilityLabel)
    XCTAssertEqual(controller.menuBarModel.timeRemaining, 29)
    // The label keeps the full time even though the bar shows minutes only.
    XCTAssertTrue(
      (statusItem.button?.accessibilityLabel() ?? "").contains(String(29)))
  }
}
