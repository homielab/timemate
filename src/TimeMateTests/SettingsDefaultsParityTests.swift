//  Created by homielab.com

import XCTest

@testable import TimeMate

/// `SettingsKey.registerDefaults` and the fallbacks `PomodoroTimer` uses when a key was
/// never written both state a default; they must not drift apart.
final class SettingsDefaultsParityTests: XCTestCase {
  private let suiteName = "TimeMateDefaultsParityTests"
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: suiteName)
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults = nil
    UserDefaults().removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  private func makeTimer(
    _ defaults: UserDefaults, fullscreen: Bool = false
  ) -> PomodoroTimer {
    PomodoroTimer(
      defaults: defaults, history: SessionHistory(fileURL: nil),
      isFullscreenProbe: { fullscreen })
  }

  func testTimerFallbacksMatchRegisteredDefaults() throws {
    let unset = makeTimer(defaults)
    let unsetFullscreen = makeTimer(defaults, fullscreen: true)

    let registered = try XCTUnwrap(UserDefaults(suiteName: suiteName + ".registered"))
    registered.removePersistentDomain(forName: suiteName + ".registered")
    defer { registered.removePersistentDomain(forName: suiteName + ".registered") }
    SettingsKey.registerDefaults(in: registered)
    let timer = makeTimer(registered)
    let fullscreenTimer = makeTimer(registered, fullscreen: true)

    XCTAssertEqual(unset.keepBreakScreenOpen, timer.keepBreakScreenOpen)
    XCTAssertEqual(unset.notificationsEnabled, timer.notificationsEnabled)
    XCTAssertEqual(unset.breakThroughFocus, timer.breakThroughFocus)
    XCTAssertEqual(unset.dailyGoal, timer.dailyGoal)
    XCTAssertEqual(unset.autoStart.breaks, timer.autoStart.breaks)
    XCTAssertEqual(unset.autoStart.focus, timer.autoStart.focus)
    XCTAssertEqual(unset.idlePauseMinutes, timer.idlePauseMinutes)
    // Overlay switch and "skip when a full-screen app is in front".
    XCTAssertEqual(unset.breakScreenCanShow, timer.breakScreenCanShow)
    XCTAssertEqual(unsetFullscreen.breakScreenCanShow, fullscreenTimer.breakScreenCanShow)
  }

  func testSwitchesReadAsBoolAreRegisteredOff() {
    // Read with `bool(forKey:)` (false when unset), so their registered value must be false.
    SettingsKey.registerDefaults(in: defaults)
    for key in [
      SettingsKey.keepAwake, SettingsKey.alwaysVisible, SettingsKey.autoStartOnLaunch,
      SettingsKey.showTimerAtLogin, SettingsKey.overlayWaitDuringCalls,
    ] {
      XCTAssertEqual(defaults.object(forKey: key) as? Bool, false, key)
    }
  }
}
