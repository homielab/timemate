//  Created by homielab.com

import AppKit
import XCTest

@testable import TimeMate

final class BreakOverlayWindowControllerTests: XCTestCase {
  private static let suiteName = "TimeMateBreakOverlayWindowControllerTests"

  private var defaults: UserDefaults!
  private var currentTime = Date(timeIntervalSince1970: 1_000_000)
  private var timer: PomodoroTimer!
  /// Fade-outs the controller started; the test ends them (`done`) when it wants.
  private var fadeOuts: [() -> Void] = []

  override func setUp() {
    super.setUp()
    fadeOuts = []
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
    defaults.set(30, forKey: SettingsKey.focusDuration)
    defaults.set(10, forKey: SettingsKey.shortBreakDuration)
    defaults.set(5, forKey: SettingsKey.overlaySkipDelay)
    defaults.set(true, forKey: SettingsKey.overlayEnabled)
    defaults.set(false, forKey: SettingsKey.overlaySkipFullscreen)
    defaults.set(true, forKey: SettingsKey.autoStartNextSession)
    defaults.set(false, forKey: SettingsKey.notificationsEnabled)
    defaults.set(0.0, forKey: SettingsKey.alarmVolume)

    timer = PomodoroTimer(
      defaults: defaults,
      now: { [weak self] in self?.currentTime ?? Date(timeIntervalSince1970: 0) },
      workspaceNotificationCenter: NotificationCenter(),
      history: SessionHistory(fileURL: nil),
      isFullscreenProbe: { false })
  }

  override func tearDown() {
    timer = nil
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  private func makeController(animated: Bool) -> BreakOverlayWindowController {
    BreakOverlayWindowController(
      timer: timer, defaults: defaults, animated: animated, isFullscreenProbe: { false },
      runFade: { [weak self] windows, alpha, _, done in
        // Window animations need an unlocked screen: set the end state, finish later.
        for window in windows { window.alphaValue = alpha }
        if alpha == 0 { self?.fadeOuts.append(done) } else { done() }
      })
  }

  private func runTicks(_ count: Int) {
    for _ in 0..<count {
      currentTime = currentTime.addingTimeInterval(1)
      timer.handleTick()
    }
  }

  private func postScreenChange() {
    NotificationCenter.default.post(
      name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
    drainMainQueue()
  }

  func testScreenChangeDuringBreakKeepsTheSkipCountdown() {
    let controller = makeController(animated: false)
    timer.startTimer()
    timer.skipSession()
    drainMainQueue()
    XCTAssertTrue(controller.isShowingOverlay)
    runTicks(3)
    XCTAssertEqual(controller.model.countdown.skipSecondsRemaining, 2)

    postScreenChange()

    XCTAssertTrue(controller.isShowingOverlay)
    XCTAssertTrue(controller.model.countdown.isLive, "the countdown keeps following the timer")
    XCTAssertEqual(controller.model.countdown.skipSecondsRemaining, 2)
    runTicks(1)
    XCTAssertEqual(controller.model.countdown.skipSecondsRemaining, 1)
  }

  func testNextBreakStartsTheSkipDelayOver() {
    let controller = makeController(animated: false)
    timer.startTimer()
    timer.skipSession()
    drainMainQueue()
    runTicks(3)
    XCTAssertEqual(controller.model.countdown.skipSecondsRemaining, 2)

    timer.skipSession()
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertFalse(controller.isShowingOverlay)
    XCTAssertFalse(controller.model.countdown.isLive)

    timer.skipSession()
    drainMainQueue()
    XCTAssertTrue(controller.isShowingOverlay)
    XCTAssertEqual(controller.model.countdown.skipSecondsRemaining, 5)
    runTicks(1)
    XCTAssertEqual(controller.model.countdown.skipSecondsRemaining, 4)
  }

  func testScreenChangeDuringFadeOutDoesNotBringTheOverlayBack() throws {
    try XCTSkipIf(
      BreakOverlayAccessibility.reduceMotion, "Reduce Motion is on: the overlay closes at once")
    let controller = makeController(animated: true)
    timer.startTimer()
    timer.skipSession()
    drainMainQueue()
    XCTAssertTrue(controller.isShowingOverlay)

    timer.skipSession()  // The break is over: the overlay fades out.
    XCTAssertFalse(controller.isShowingOverlay)

    postScreenChange()
    XCTAssertFalse(controller.isShowingOverlay, "a fading break screen must not come back")

    XCTAssertTrue(controller.model.countdown.isLive, "the windows stay until the fade ends")
    XCTAssertFalse(fadeOuts.isEmpty, "the overlay fades out")
    for done in fadeOuts { done() }
    let closed = waitUntil { !controller.model.countdown.isLive }
    XCTAssertTrue(closed, "the windows close when the fade ends")
    XCTAssertFalse(controller.isShowingOverlay)
  }
}
