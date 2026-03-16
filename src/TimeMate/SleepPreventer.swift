//  Created by homielab.com

import IOKit.pwr_mgt

class SleepPreventer {
  private var assertionID: IOPMAssertionID = 0
  private var isEnabled = false

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
      print("Sleep prevention enabled")
    } else {
      print("Failed to enable sleep prevention")
    }
  }

  func disable() {
    guard isEnabled else { return }

    let success = IOPMAssertionRelease(assertionID)

    if success == kIOReturnSuccess {
      self.assertionID = 0
      self.isEnabled = false
      print("Sleep prevention disabled")
    } else {
      print("Failed to disable sleep prevention")
    }
  }

  deinit {
    disable()
  }
}
