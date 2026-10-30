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
  /// Fake "another app keeps the display awake" and how often the controller read it.
  private var displayKeptAwake = false
  private var awakeProbeCalls = 0
  /// Settle re-checks the controller scheduled; `runScheduledRechecks()` runs them.
  private var scheduledRechecks: [DispatchWorkItem] = []

  override func setUp() {
    super.setUp()
    fadeOuts = []
    scheduledRechecks = []
    displayKeptAwake = false
    awakeProbeCalls = 0
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
      playSound: { _, _ in }, isFullscreenProbe: { false })
  }

  override func tearDown() {
    timer = nil
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  /// The displays the controller sees; `nil` = the real ones.
  private var fakeScreens: [NSScreen]?

  private func makeController(
    animated: Bool, tip: @escaping () -> String = RelaxationTips.random
  ) -> BreakOverlayWindowController {
    BreakOverlayWindowController(
      timer: timer, defaults: defaults, animated: animated, isFullscreenProbe: { false },
      workspaceNotificationCenter: NotificationCenter(), fallbackPollInterval: nil,
      runFade: { [weak self] windows, alpha, _, done in
        // Window animations need an unlocked screen: set the end state, finish later.
        for window in windows { window.alphaValue = alpha }
        if alpha == 0 { self?.fadeOuts.append(done) } else { done() }
      }, screenChangeDelay: nil, tip: tip,
      screens: { [weak self] in self?.fakeScreens ?? NSScreen.screens })
  }

  /// Hands out "tip 1", "tip 2", … one per pick.
  private func makeCountingTips() -> () -> String {
    var count = 0
    return {
      count += 1
      return "tip \(count)"
    }
  }

  /// A break screen that waits because the app in front is full screen (`frontmostIsFullscreen`).
  private func makeWaitingController(
    workspace: NotificationCenter, fallbackPollInterval: TimeInterval? = nil,
    settleDelay: TimeInterval? = nil
  ) -> BreakOverlayWindowController {
    defaults.set(true, forKey: SettingsKey.overlaySkipFullscreen)
    frontmostIsFullscreen = true
    let controller = BreakOverlayWindowController(
      timer: timer, defaults: defaults, animated: false,
      isFullscreenProbe: { [weak self] in self?.frontmostIsFullscreen ?? false },
      workspaceNotificationCenter: workspace, fallbackPollInterval: fallbackPollInterval,
      settleDelay: settleDelay,
      scheduleRecheck: { [weak self] _, work in self?.scheduledRechecks.append(work) })
    timer.startTimer()
    timer.skipSession()
    XCTAssertFalse(controller.isShowingOverlay)
    XCTAssertTrue(controller.isWaitingForWindowedApp)
    return controller
  }

  /// Runs the settle re-checks scheduled so far, as if their delay had passed.
  private func runScheduledRechecks() {
    let due = scheduledRechecks
    scheduledRechecks = []
    for work in due where !work.isCancelled { work.perform() }
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

  /// A controller whose "another app keeps the display awake" probe reads
  /// `displayKeptAwake` and counts its calls in `awakeProbeCalls`.
  private func makeCallAwareController(workspace: NotificationCenter)
    -> BreakOverlayWindowController
  {
    BreakOverlayWindowController(
      timer: timer, defaults: defaults, animated: false, isFullscreenProbe: { false },
      isDisplayKeptAwakeProbe: { [weak self] in
        self?.awakeProbeCalls += 1
        return self?.displayKeptAwake ?? false
      },
      workspaceNotificationCenter: workspace, fallbackPollInterval: nil)
  }

  func testBreakScreenWaitsDuringACallUntilItEnds() {
    defaults.set(true, forKey: SettingsKey.overlayWaitDuringCalls)
    displayKeptAwake = true
    let workspace = NotificationCenter()
    let controller = makeCallAwareController(workspace: workspace)
    timer.startTimer()
    timer.skipSession()
    XCTAssertFalse(controller.isShowingOverlay, "A call keeps the display awake: wait")
    XCTAssertTrue(controller.isWaitingForWindowedApp)

    displayKeptAwake = false
    workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
    drainMainQueue()
    XCTAssertTrue(controller.isShowingOverlay, "The call ended: the break screen shows")
    XCTAssertFalse(controller.isWaitingForWindowedApp)

    // Once on screen it stays, even when a call starts again.
    displayKeptAwake = true
    let calls = awakeProbeCalls
    defaults.set(false, forKey: SettingsKey.overlayWaitDuringCalls)
    defaults.set(true, forKey: SettingsKey.overlayWaitDuringCalls)
    XCTAssertTrue(controller.isShowingOverlay)
    XCTAssertEqual(awakeProbeCalls, calls, "Not probed while the break screen is visible")
  }

  func testSkipDelayBlocksOtherPathsOnlyWhileTheBreakScreenShows() {
    defaults.set(true, forKey: SettingsKey.overlayWaitDuringCalls)
    displayKeptAwake = true
    let workspace = NotificationCenter()
    let controller = makeCallAwareController(workspace: workspace)
    timer.startTimer()
    timer.skipSession()
    XCTAssertFalse(controller.isShowingOverlay)
    XCTAssertEqual(timer.skipLockSeconds, 0, "Waiting break screen: nothing blocked")

    displayKeptAwake = false
    workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
    drainMainQueue()
    XCTAssertTrue(controller.isShowingOverlay)
    XCTAssertEqual(timer.skipLockSeconds, 5)
    XCTAssertNotNil(timer.perform(.skip))
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
  }

  func testBreakScreenShowsDuringACallWhenTheSettingIsOff() {
    displayKeptAwake = true
    let controller = makeCallAwareController(workspace: NotificationCenter())
    timer.startTimer()
    timer.skipSession()
    XCTAssertTrue(controller.isShowingOverlay)
    XCTAssertEqual(awakeProbeCalls, 0, "Off by default: the assertions are not read")
  }

  func testTurningOnWaitDuringCallsReevaluatesAWaitingBreak() {
    displayKeptAwake = true
    defaults.set(true, forKey: SettingsKey.overlayWaitDuringCalls)
    let controller = makeCallAwareController(workspace: NotificationCenter())
    timer.startTimer()
    timer.skipSession()
    XCTAssertTrue(controller.isWaitingForWindowedApp)
    defaults.set(false, forKey: SettingsKey.overlayWaitDuringCalls)
    XCTAssertTrue(controller.isShowingOverlay, "Setting off: shown right away")
  }

  func testSpaceChangeDuringFullscreenAnimationIsCheckedAgainOnceSettled() {
    let workspace = NotificationCenter()
    let controller = makeWaitingController(workspace: workspace, settleDelay: 0.05)

    // The Space changes when leaving full screen starts: the window is still listed.
    workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    drainMainQueue()
    XCTAssertFalse(controller.isShowingOverlay)
    XCTAssertTrue(controller.hasPendingSettleRecheck)

    frontmostIsFullscreen = false
    runScheduledRechecks()
    XCTAssertTrue(controller.isShowingOverlay, "shown without the fallback poll")
    XCTAssertFalse(controller.isWaitingForWindowedApp)
    XCTAssertFalse(controller.hasPendingSettleRecheck)
  }

  func testSettleRechecksInABurstRunOnce() {
    let workspace = NotificationCenter()
    let controller = makeWaitingController(workspace: workspace, settleDelay: 0.05)

    workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
    controller.handleClickWhileWaiting()
    drainMainQueue()
    let evaluations = controller.evaluationCount
    XCTAssertTrue(controller.hasPendingSettleRecheck)

    runScheduledRechecks()

    XCTAssertEqual(controller.evaluationCount, evaluations + 1)
    XCTAssertFalse(controller.hasPendingSettleRecheck)
    XCTAssertTrue(controller.isWaitingForWindowedApp, "still full screen")
  }

  func testClicksWhileWaitingScheduleAThrottledRecheck() {
    let controller = makeWaitingController(workspace: NotificationCenter(), settleDelay: 0.05)
    XCTAssertTrue(controller.isMonitoringClicks)
    let start = Date(timeIntervalSince1970: 2_000_000_000)

    controller.handleClickWhileWaiting(now: start)
    XCTAssertTrue(controller.hasPendingSettleRecheck)
    runScheduledRechecks()
    XCTAssertFalse(controller.hasPendingSettleRecheck)
    controller.handleClickWhileWaiting(now: start.addingTimeInterval(0.5))
    XCTAssertFalse(controller.hasPendingSettleRecheck, "at most one per second")
    XCTAssertTrue(scheduledRechecks.isEmpty)

    frontmostIsFullscreen = false
    controller.handleClickWhileWaiting(now: start.addingTimeInterval(1.1))
    XCTAssertTrue(controller.hasPendingSettleRecheck)
    XCTAssertFalse(controller.isShowingOverlay, "not before the settle delay")
    runScheduledRechecks()
    XCTAssertTrue(controller.isShowingOverlay)
    XCTAssertFalse(controller.isMonitoringClicks, "the click monitor is removed once shown")
  }

  func testBreakEndingWhileWaitingCancelsTheSettleRecheck() {
    let workspace = NotificationCenter()
    let controller = makeWaitingController(workspace: workspace, settleDelay: 0.05)
    workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    drainMainQueue()
    XCTAssertTrue(controller.hasPendingSettleRecheck)

    timer.skipSession()

    XCTAssertFalse(controller.hasPendingSettleRecheck)
    XCTAssertFalse(controller.isMonitoringClicks)
    XCTAssertTrue(scheduledRechecks.allSatisfy(\.isCancelled), "the cancelled re-check never runs")
  }

  func testNoBackgroundChecksWhileWaitingWithoutFallbackPoll() {
    let controller = makeWaitingController(workspace: NotificationCenter())

    XCTAssertTrue(controller.isWaitingForWindowedApp)
    XCTAssertFalse(controller.hasFallbackPoll, "no interval, no poll")
  }

  func testBreakEndingWhileWaitingStopsTheFallbackPoll() {
    let controller = makeWaitingController(
      workspace: NotificationCenter(), fallbackPollInterval: 0.05)
    XCTAssertTrue(controller.hasFallbackPoll)
    var evaluations = controller.evaluationCount
    XCTAssertTrue(waitUntil { controller.evaluationCount > evaluations }, "the poll runs")

    timer.skipSession()

    XCTAssertFalse(controller.hasFallbackPoll)
    XCTAssertFalse(controller.isWaitingForWindowedApp)
    evaluations = controller.evaluationCount
    XCTAssertFalse(
      waitUntil(timeout: 0.2) { controller.evaluationCount > evaluations },
      "the poll no longer runs")
  }

  func testFallbackPollReevaluatesWhileWaiting() {
    let controller = makeWaitingController(
      workspace: NotificationCenter(), fallbackPollInterval: 0.05)
    let evaluations = controller.evaluationCount

    XCTAssertTrue(waitUntil { controller.evaluationCount > evaluations })
    frontmostIsFullscreen = false
    XCTAssertTrue(waitUntil { controller.isShowingOverlay })
    XCTAssertFalse(controller.isWaitingForWindowedApp)
    XCTAssertFalse(controller.hasFallbackPoll, "the poll stops once shown")
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

  func testBreakScreenComesBackAfterAllScreensWentAway() {
    let controller = makeController(animated: false)
    timer.startTimer()
    timer.skipSession()
    drainMainQueue()
    runTicks(3)
    let windowCount = controller.windowTitles.count
    XCTAssertGreaterThan(windowCount, 0)

    fakeScreens = []
    postScreenChange()
    XCTAssertTrue(controller.windowTitles.isEmpty)

    fakeScreens = nil
    postScreenChange()
    XCTAssertEqual(controller.windowTitles.count, windowCount)
    XCTAssertTrue(controller.isShowingOverlay)
    XCTAssertEqual(controller.windowSkipsEntrance, Array(repeating: true, count: windowCount))
    XCTAssertEqual(controller.model.countdown.skipSecondsRemaining, 2)
  }

  func testRestoredBreakKeepsItsSkipDelay() {
    var first: BreakOverlayWindowController? = makeController(animated: false)
    timer.startTimer()
    timer.skipSession()
    drainMainQueue()
    XCTAssertNotNil(timer.breakScreenShownAt)
    runTicks(3)
    timer.prepareForRelaunch()
    _ = first
    first = nil

    currentTime = currentTime.addingTimeInterval(1)
    timer = PomodoroTimer(
      defaults: defaults,
      now: { [weak self] in self?.currentTime ?? Date(timeIntervalSince1970: 0) },
      workspaceNotificationCenter: NotificationCenter(),
      history: SessionHistory(fileURL: nil),
      playSound: { _, _ in }, isFullscreenProbe: { false })
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
    let controller = makeController(animated: false)
    drainMainQueue()
    XCTAssertTrue(controller.isShowingOverlay)
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

  func testEveryScreenShowsTheSameTipForTheWholeBreak() {
    let controller = makeController(animated: false, tip: makeCountingTips())
    timer.startTimer()
    timer.skipSession()
    drainMainQueue()
    XCTAssertTrue(controller.isShowingOverlay)
    let tip = controller.model.tip
    XCTAssertFalse(controller.windowTips.isEmpty)
    XCTAssertEqual(Set(controller.windowTips), [tip])

    postScreenChange()

    XCTAssertEqual(controller.model.tip, tip, "rebuilding the windows keeps the tip")
    XCTAssertEqual(Set(controller.windowTips), [tip])
  }

  func testEveryBreakWindowHasATitleForVoiceOver() {
    let controller = makeController(animated: false)
    timer.startTimer()
    timer.skipSession()
    drainMainQueue()
    XCTAssertTrue(controller.isShowingOverlay)
    XCTAssertFalse(controller.windowTitles.isEmpty)
    XCTAssertTrue(controller.windowTitles.allSatisfy { !$0.isEmpty })
    XCTAssertEqual(Set(controller.windowTitles), [BreakOverlayAccessibility.windowTitle()])
  }

  func testNextBreakPicksANewTip() {
    let controller = makeController(animated: false, tip: makeCountingTips())
    timer.startTimer()
    timer.skipSession()
    drainMainQueue()
    let firstTip = controller.model.tip

    timer.skipSession()
    XCTAssertFalse(controller.isShowingOverlay)
    XCTAssertEqual(controller.model.tip, firstTip)

    timer.skipSession()
    drainMainQueue()
    XCTAssertTrue(controller.isShowingOverlay)
    XCTAssertNotEqual(controller.model.tip, firstTip)
    XCTAssertEqual(Set(controller.windowTips), [controller.model.tip])
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

  func testScreenChangeRebuildsWindowsWithoutTheEntrance() {
    let controller = makeController(animated: false)
    timer.startTimer()
    timer.skipSession()
    drainMainQueue()
    XCTAssertEqual(Set(controller.windowSkipsEntrance), [false], "the first show animates in")
    let tip = controller.model.tip

    postScreenChange()

    XCTAssertEqual(Set(controller.windowSkipsEntrance), [true])
    XCTAssertEqual(Set(controller.windowTips), [tip])
  }

  func testScreenChangesAreCoalesced() {
    var scheduled: [(TimeInterval, DispatchWorkItem)] = []
    let controller = BreakOverlayWindowController(
      timer: timer, defaults: defaults, animated: false, isFullscreenProbe: { false },
      workspaceNotificationCenter: NotificationCenter(), fallbackPollInterval: nil,
      settleDelay: nil, scheduleRecheck: { scheduled.append(($0, $1)) },
      runFade: { windows, alpha, _, done in
        for window in windows { window.alphaValue = alpha }
        done()
      })
    timer.startTimer()
    timer.skipSession()
    drainMainQueue()

    postScreenChange()
    postScreenChange()

    XCTAssertEqual(scheduled.count, 2)
    XCTAssertTrue(scheduled[0].1.isCancelled, "a newer change replaces the pending rebuild")
    XCTAssertEqual(scheduled[1].0, BreakOverlayWindowController.screenChangeDelay)
    XCTAssertEqual(Set(controller.windowSkipsEntrance), [false], "no rebuild before the delay")
    scheduled[1].1.perform()
    XCTAssertEqual(Set(controller.windowSkipsEntrance), [true])
  }
}
