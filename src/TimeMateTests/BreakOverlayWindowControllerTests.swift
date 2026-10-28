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
  private var frontmostIsFullscreen = false

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
      workspaceNotificationCenter: NotificationCenter(), fallbackPollInterval: nil,
      runFade: { [weak self] windows, alpha, _, done in
        // Window animations need an unlocked screen: set the end state, finish later.
        for window in windows { window.alphaValue = alpha }
        if alpha == 0 { self?.fadeOuts.append(done) } else { done() }
      })
  }

  /// A break screen that waits because the app in front is full screen (`frontmostIsFullscreen`).
  private func makeWaitingController(
    workspace: NotificationCenter, fallbackPollInterval: TimeInterval? = nil
  ) -> BreakOverlayWindowController {
    defaults.set(true, forKey: SettingsKey.overlaySkipFullscreen)
    frontmostIsFullscreen = true
    let controller = BreakOverlayWindowController(
      timer: timer, defaults: defaults, animated: false,
      isFullscreenProbe: { [weak self] in self?.frontmostIsFullscreen ?? false },
      workspaceNotificationCenter: workspace, fallbackPollInterval: fallbackPollInterval)
    timer.startTimer()
    timer.skipSession()
    XCTAssertFalse(controller.isShowingOverlay)
    XCTAssertTrue(controller.isWaitingForWindowedApp)
    return controller
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

  func testSpaceOrAppChangeReevaluatesOnceWhileWaitingForFullscreen() {
    let workspace = NotificationCenter()
    let controller = makeWaitingController(workspace: workspace)

    var evaluations = controller.evaluationCount
    workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    drainMainQueue()
    XCTAssertEqual(controller.evaluationCount, evaluations + 1)
    XCTAssertFalse(controller.isShowingOverlay, "Still full screen: keeps waiting")

    frontmostIsFullscreen = false
    evaluations = controller.evaluationCount
    workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
    drainMainQueue()
    XCTAssertEqual(controller.evaluationCount, evaluations + 1)
    XCTAssertTrue(controller.isShowingOverlay, "The app in front left full screen")
    XCTAssertFalse(controller.isWaitingForWindowedApp)

    evaluations = controller.evaluationCount
    workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    drainMainQueue()
    XCTAssertEqual(controller.evaluationCount, evaluations, "Observers removed once shown")
  }

  func testNoBackgroundChecksWhileWaitingWithoutFallbackPoll() {
    let controller = makeWaitingController(workspace: NotificationCenter())
    let evaluations = controller.evaluationCount

    RunLoop.main.run(until: Date().addingTimeInterval(6))

    XCTAssertEqual(controller.evaluationCount, evaluations)
    XCTAssertTrue(controller.isWaitingForWindowedApp)
  }

  func testFallbackPollReevaluatesWhileWaiting() {
    let controller = makeWaitingController(
      workspace: NotificationCenter(), fallbackPollInterval: 0.05)
    let evaluations = controller.evaluationCount

    XCTAssertTrue(waitUntil { controller.evaluationCount > evaluations })
    frontmostIsFullscreen = false
    XCTAssertTrue(waitUntil { controller.isShowingOverlay })
    XCTAssertFalse(controller.isWaitingForWindowedApp)
  }

  func testBreakEndingWhileWaitingRemovesTheObservers() {
    let workspace = NotificationCenter()
    let controller = makeWaitingController(workspace: workspace)

    timer.skipSession()
    XCTAssertFalse(controller.isWaitingForWindowedApp)

    let evaluations = controller.evaluationCount
    workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    drainMainQueue()
    XCTAssertEqual(controller.evaluationCount, evaluations)
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
