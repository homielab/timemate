//  Created by homielab.com

import Foundation
import IOKit.pwr_mgt

/// Whether another app holds a power assertion that keeps the display awake,
/// as Zoom, Teams, FaceTime, browsers and video players do during a call or
/// while a video plays. Reads assertions only (no entitlement, works in the
/// sandbox); TimeMate's own assertions don't count.
enum DisplayAwakeProbe {
  /// Assertion types that keep the display on.
  static let displayTypes: Set<String> = [
    "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion",
  ]

  /// True when a process other than `ownPID` holds an active display assertion.
  /// `assertionsByPID` has the shape of `IOPMCopyAssertionsByProcess`.
  static func isKeptAwake(assertionsByPID: [Int: [[String: Any]]], ownPID: Int) -> Bool {
    assertionsByPID.contains { pid, assertions in
      pid != ownPID
        && assertions.contains { assertion in
          guard let type = assertion["AssertType"] as? String, displayTypes.contains(type)
          else { return false }
          // Missing level: the assertion is listed, so treat it as on.
          return (assertion["AssertLevel"] as? Int ?? 255) != 0
        }
    }
  }

  /// The live check; false when the assertions can't be read.
  static func isKeptAwakeByOtherApp() -> Bool {
    var unmanaged: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
      let raw = unmanaged?.takeRetainedValue() as NSDictionary?
    else { return false }
    var byPID: [Int: [[String: Any]]] = [:]
    for (key, value) in raw {
      guard let pid = (key as? NSNumber)?.intValue, let list = value as? [[String: Any]]
      else { continue }
      byPID[pid] = list
    }
    return isKeptAwake(assertionsByPID: byPID, ownPID: Int(getpid()))
  }
}
