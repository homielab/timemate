//  Created by homielab.com

import XCTest

@testable import TimeMate

final class BreakOverlayToggleTests: XCTestCase {
  private static let suiteName = "TimeMateBreakOverlayToggleTests"

  private var defaults: UserDefaults!
  private var timer: PomodoroTimer!
  private var controller: BreakOverlayWindowController!

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
    defaults.set(true, forKey: SettingsKey.overlayEnabled)
    defaults.set(false, forKey: SettingsKey.overlaySkipFullscreen)
    defaults.set(true, forKey: SettingsKey.autoStartNextSession)
    defaults.set(false, forKey: SettingsKey.notificationsEnabled)
    defaults.set(0.0, forKey: SettingsKey.alarmVolume)

    timer = PomodoroTimer(
      defaults: defaults,
      workspaceNotificationCenter: NotificationCenter(),
      history: SessionHistory(fileURL: nil), isFullscreenProbe: { false })

    controller = BreakOverlayWindowController(timer: timer, defaults: defaults, animated: false)
  }

  override func tearDown() {
    controller = nil
    timer = nil
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  func testToggleOverlayDuringBreakShowsAndHidesOverlay() {
    timer.startTimer()
    timer.skipSession()

    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    XCTAssertEqual(timer.state, .active)
    XCTAssertTrue(controller.isShowingOverlay, "Overlay shows when break starts with setting on")

    // Turn off overlay in Settings during the break
    defaults.set(false, forKey: SettingsKey.overlayEnabled)
    XCTAssertFalse(
      controller.isShowingOverlay, "Overlay hides immediately when disabled during break")

    // Turn it back on
    defaults.set(true, forKey: SettingsKey.overlayEnabled)
    XCTAssertTrue(
      controller.isShowingOverlay, "Overlay re-appears immediately when re-enabled during break")
  }

  func testToggleOverlayDuringWaitingBreak() {
    timer.currentSessionType = .shortBreak
    timer.state = .idle
    timer.isWaitingToContinue = true

    XCTAssertTrue(controller.isShowingOverlay, "Overlay should show on waiting break screen")

    defaults.set(false, forKey: SettingsKey.overlayEnabled)
    XCTAssertFalse(
      controller.isShowingOverlay, "Overlay should hide when disabled while waiting")

    defaults.set(true, forKey: SettingsKey.overlayEnabled)
    XCTAssertTrue(
      controller.isShowingOverlay, "Overlay should re-appear when re-enabled while waiting")
  }

  func testTickModeUsesBreakOverlayRules() {
    let modeWithOverlay = TickMode.mode(
      popoverOpen: false,
      menuBarStyle: .iconOnly,
      breakOverlayShown: BreakOverlayRules.shouldShowOverlay(
        state: .active,
        sessionType: .shortBreak,
        isWaiting: false,
        isPostponed: false,
        enabled: true
      ),
      voiceOverRunning: false
    )
    XCTAssertEqual(modeWithOverlay, .everySecond)

    let modeWithoutOverlay = TickMode.mode(
      popoverOpen: false,
      menuBarStyle: .iconOnly,
      breakOverlayShown: BreakOverlayRules.shouldShowOverlay(
        state: .active,
        sessionType: .shortBreak,
        isWaiting: false,
        isPostponed: false,
        enabled: false
      ),
      voiceOverRunning: false
    )
    XCTAssertEqual(modeWithoutOverlay, .atEnd)
  }
}
