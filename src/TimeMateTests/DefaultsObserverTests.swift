//  Created by homielab.com

import XCTest

@testable import TimeMate

final class DefaultsObserverTests: XCTestCase {
  private static let suiteName = "DefaultsObserverTests"
  private var defaults: UserDefaults!
  private var observer: DefaultsObserver?
  private var calls = 0

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: Self.suiteName)
    defaults = UserDefaults(suiteName: Self.suiteName)
    calls = 0
    observer = DefaultsObserver(
      defaults: defaults, keys: [SettingsKey.overlayEnabled, SettingsKey.focusDuration]
    ) { [unowned self] in calls += 1 }
  }

  override func tearDown() {
    observer = nil
    defaults.removePersistentDomain(forName: Self.suiteName)
    super.tearDown()
  }

  func testWatchedKeyChangeCallsOnce() {
    defaults.set(false, forKey: SettingsKey.overlayEnabled)
    XCTAssertEqual(calls, 1)
  }

  func testUnrelatedWritesAreIgnored() {
    defaults.set("Write docs", forKey: SettingsKey.sessionLabel)
    defaults.set(0.4, forKey: SettingsKey.alarmVolume)
    XCTAssertEqual(calls, 0)
  }

  func testSameValueWrittenAgainIsIgnored() {
    defaults.set(30, forKey: SettingsKey.focusDuration)
    defaults.set(30, forKey: SettingsKey.focusDuration)
    XCTAssertEqual(calls, 1)
  }

  func testRemovingAKeyCounts() {
    defaults.set(30, forKey: SettingsKey.focusDuration)
    defaults.removeObject(forKey: SettingsKey.focusDuration)
    XCTAssertEqual(calls, 2)
  }

  func testWriteFromBackgroundThreadHopsToMain() {
    let done = expectation(description: "handler")
    observer = DefaultsObserver(defaults: defaults, keys: [SettingsKey.focusDuration]) {
      XCTAssertTrue(Thread.isMainThread)
      done.fulfill()
    }
    DispatchQueue.global().async { self.defaults.set(45, forKey: SettingsKey.focusDuration) }
    wait(for: [done], timeout: 2)
  }

  func testStopsAfterRelease() {
    observer = nil
    defaults.set(10, forKey: SettingsKey.focusDuration)
    XCTAssertEqual(calls, 0)
  }
}
