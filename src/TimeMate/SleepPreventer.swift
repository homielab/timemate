//  Created by homielab.com

import IOKit.pwr_mgt

class SleepPreventer {
  private var assertionID: IOPMAssertionID = 0
  private var isEnabled = false

  /// The Mac is kept awake only while the setting is on AND a focus session is counting down.
  static func shouldHoldAssertion(
    keepAwake: Bool, state: PomodoroState, sessionType: SessionType
  ) -> Bool {
    keepAwake && state == .active && sessionType == .focus
  }

  func enable() {
    guard !isEnabled else { return }

    var assertionID: IOPMAssertionID = 0
    let reason = "TimeMate - Keep Mac awake during timer" as CFString
    let assertionType = kIOPMAssertionTypeNoIdleSleep as CFString

    let success = IOPMAssertionCreateWithName(
      assertionType,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      reason,
      &assertionID
    )

    if success == kIOReturnSuccess {
      self.assertionID = assertionID
      self.isEnabled = true
    }
  }

  func disable() {
    guard isEnabled else { return }

    let success = IOPMAssertionRelease(assertionID)

    if success == kIOReturnSuccess {
      self.assertionID = 0
      self.isEnabled = false
    }
  }

  deinit {
    disable()
  }
}
