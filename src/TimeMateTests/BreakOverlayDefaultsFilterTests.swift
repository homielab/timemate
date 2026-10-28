//  Created by homielab.com

import XCTest

@testable import TimeMate

final class BreakOverlayDefaultsFilterTests: XCTestCase {
  private static let suiteName = "TimeMateBreakOverlayDefaultsFilterTests"

  private var defaults: UserDefaults!
  private var timer: PomodoroTimer!
  private var controller: BreakOverlayWindowController!
  private var probeCalls = 0

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
    defaults.set(true, forKey: SettingsKey.overlayEnabled)
    defaults.set(true, forKey: SettingsKey.overlaySkipFullscreen)
    defaults.set(true, forKey: SettingsKey.autoStartNextSession)
    defaults.set(false, forKey: SettingsKey.notificationsEnabled)
    defaults.set(0.0, forKey: SettingsKey.alarmVolume)
    probeCalls = 0

    timer = PomodoroTimer(
      defaults: defaults,
      workspaceNotificationCenter: NotificationCenter(),
      history: SessionHistory(fileURL: nil), isFullscreenProbe: { false })
    controller = BreakOverlayWindowController(
      timer: timer, defaults: defaults, animated: false,
      isFullscreenProbe: { [unowned self] in
        self.probeCalls += 1
        return false
      })
  }

  override func tearDown() {
    controller = nil
    timer = nil
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  func testUnrelatedWritesDuringBreakDoNotReevaluate() {
    timer.startTimer()
    timer.skipSession()
    XCTAssertTrue(controller.isShowingOverlay)
    let evaluations = controller.evaluationCount
    let probes = probeCalls

    defaults.set(0.5, forKey: SettingsKey.alarmVolume)
    defaults.set("{}", forKey: SettingsKey.timerSnapshot)
    defaults.set(0.7, forKey: SettingsKey.alarmVolume)

    XCTAssertEqual(controller.evaluationCount, evaluations)
    XCTAssertEqual(probeCalls, probes)
  }

  func testProbeIsSkippedWhileOverlayIsVisible() {
    timer.startTimer()
    timer.skipSession()
    XCTAssertTrue(controller.isShowingOverlay)
    let probes = probeCalls

    defaults.set(false, forKey: SettingsKey.overlaySkipFullscreen)
    defaults.set(true, forKey: SettingsKey.overlaySkipFullscreen)

    XCTAssertEqual(probeCalls, probes, "No lookup once the break screen is already showing")
  }

  func testProbeIsNotCalledOutsideABreak() {
    timer.startTimer()
    defaults.set(false, forKey: SettingsKey.overlaySkipFullscreen)
    defaults.set(true, forKey: SettingsKey.overlaySkipFullscreen)
    XCTAssertEqual(probeCalls, 0)
  }

  func testChangingSkipFullscreenReevaluatesAndProbes() {
    defaults.set(false, forKey: SettingsKey.overlaySkipFullscreen)
    timer.startTimer()
    timer.skipSession()
    controller = nil
    probeCalls = 0
    // Hide the overlay by disabling it, then re-enable it with the skip option on.
    controller = BreakOverlayWindowController(
      timer: timer, defaults: defaults, animated: false,
      isFullscreenProbe: { [unowned self] in
        self.probeCalls += 1
        return true
      })
    XCTAssertTrue(controller.isShowingOverlay)
    defaults.set(false, forKey: SettingsKey.overlayEnabled)
    XCTAssertFalse(controller.isShowingOverlay)

    let evaluations = controller.evaluationCount
    defaults.set(true, forKey: SettingsKey.overlaySkipFullscreen)
    defaults.set(true, forKey: SettingsKey.overlayEnabled)
    XCTAssertGreaterThan(controller.evaluationCount, evaluations)
    XCTAssertGreaterThan(probeCalls, 0)
    XCTAssertFalse(controller.isShowingOverlay, "Full-screen app in front: break screen waits")
  }

  func testOverlaySettingsEquality() {
    XCTAssertEqual(
      OverlaySettings(enabled: true, skipFullscreen: false),
      OverlaySettings(enabled: true, skipFullscreen: false))
    XCTAssertNotEqual(
      OverlaySettings(enabled: true, skipFullscreen: false),
      OverlaySettings(enabled: true, skipFullscreen: true))
    XCTAssertNotEqual(
      OverlaySettings(enabled: false, skipFullscreen: true),
      OverlaySettings(enabled: true, skipFullscreen: true))
  }
}
