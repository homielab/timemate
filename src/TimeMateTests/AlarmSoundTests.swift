//  Created by homielab.com

import AppKit
import XCTest

@testable import TimeMate

final class AlarmSoundTests: XCTestCase {
  private static let suiteName = "TimeMateAlarmSoundTests"
  private var defaults: UserDefaults!
  private var currentTime: Date!
  private var played: [String] = []

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
    // Debug builds read minutes as seconds.
    defaults.set(3, forKey: SettingsKey.focusDuration)
    defaults.set(2, forKey: SettingsKey.shortBreakDuration)
    defaults.set(true, forKey: SettingsKey.autoStartNextSession)
    defaults.set(false, forKey: SettingsKey.keepBreakScreenOpen)
    defaults.set(false, forKey: SettingsKey.notificationsEnabled)
    currentTime = Date(timeIntervalSince1970: 1_000_000)
    played = []
  }

  override func tearDown() {
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  // MARK: - Choosing the sound

  func testDefaultsAreGlassForBothSounds() {
    XCTAssertEqual(AlarmSound.sound(afterCompleting: .focus, in: defaults), "Glass")
    XCTAssertEqual(AlarmSound.sound(afterCompleting: .shortBreak, in: defaults), "Glass")
  }

  func testBreakEndSoundFallsBackToTheAlarmSound() {
    defaults.set("Ping", forKey: SettingsKey.alarmSound)
    XCTAssertEqual(AlarmSound.sound(afterCompleting: .longBreak, in: defaults), "Ping")
  }

  func testBreaksUseTheBreakEndSound() {
    defaults.set("Ping", forKey: SettingsKey.alarmSound)
    defaults.set("Hero", forKey: SettingsKey.breakEndSound)
    XCTAssertEqual(AlarmSound.sound(afterCompleting: .focus, in: defaults), "Ping")
    XCTAssertEqual(AlarmSound.sound(afterCompleting: .shortBreak, in: defaults), "Hero")
    XCTAssertEqual(AlarmSound.sound(afterCompleting: .longBreak, in: defaults), "Hero")
  }

  func testOptionsStartWithNoneAndKeepTheSystemSounds() {
    XCTAssertEqual(AlarmSound.options.first, AlarmSound.none)
    XCTAssertEqual(Array(AlarmSound.options.dropFirst()), AlarmSound.systemSounds)
  }

  // MARK: - Playing

  func testNonePlaysNothingAndLoadsNothing() {
    var loaded: [String] = []
    let started = AlarmSound.play(AlarmSound.none, volume: 1) { name in
      loaded.append(name)
      return nil
    }
    XCTAssertFalse(started)
    XCTAssertEqual(loaded, [])
  }

  func testASoundThatCannotLoadIsNotPlayed() {
    var loaded: [String] = []
    let started = AlarmSound.play("Missing", volume: 1) { name in
      loaded.append(name)
      return nil
    }
    XCTAssertFalse(started)
    XCTAssertEqual(loaded, ["Missing"])
  }

  func testEverySystemSoundLoads() {
    for name in AlarmSound.systemSounds {
      XCTAssertNotNil(NSSound(named: name), name)
    }
  }

  // MARK: - Timer

  private func makeTimer() -> PomodoroTimer {
    PomodoroTimer(
      defaults: defaults, now: { [unowned self] in self.currentTime },
      workspaceNotificationCenter: NotificationCenter(), notificationCenter: NotificationCenter(),
      postNotification: { _ in }, playSound: { [unowned self] name, _ in self.played.append(name) })
  }

  func testFocusEndPlaysTheAlarmAndBreakEndPlaysTheBreakEndSound() {
    defaults.set("Ping", forKey: SettingsKey.alarmSound)
    defaults.set("Hero", forKey: SettingsKey.breakEndSound)
    let timer = makeTimer()
    timer.startTimer()
    currentTime += 3
    timer.handleTick()
    XCTAssertEqual(timer.currentSessionType, .shortBreak)
    currentTime += 2
    timer.handleTick()
    XCTAssertEqual(timer.currentSessionType, .focus)
    XCTAssertEqual(played, ["Ping", "Hero"])
    timer.stopTimer()
  }

  func testBreakEndWithoutItsOwnSoundPlaysTheAlarm() {
    defaults.set("Ping", forKey: SettingsKey.alarmSound)
    let timer = makeTimer()
    timer.startTimer()
    currentTime += 3
    timer.handleTick()
    currentTime += 2
    timer.handleTick()
    XCTAssertEqual(played, ["Ping", "Ping"])
    timer.stopTimer()
  }

  func testNoneIsHandedToThePlayerWhichSkipsIt() {
    defaults.set(AlarmSound.none, forKey: SettingsKey.alarmSound)
    let timer = makeTimer()
    timer.startTimer()
    currentTime += 3
    timer.handleTick()
    XCTAssertEqual(played, [AlarmSound.none])
    XCTAssertFalse(AlarmSound.play(played[0], volume: 1))
    timer.stopTimer()
  }
}
