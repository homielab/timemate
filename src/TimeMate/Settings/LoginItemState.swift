//  Created by homielab.com

import ServiceManagement
import os

/// What the Start at Login toggle shows for a login item registration status.
struct LoginItemState: Equatable {
  let isOn: Bool
  let needsApproval: Bool

  init(from status: SMAppService.Status) {
    isOn = (status == .enabled || status == .requiresApproval)
    needsApproval = (status == .requiresApproval)
  }
}

/// Resetting settings also turns Start at Login off, since the registration lives
/// outside UserDefaults.
enum LoginItemReset {
  /// Calls `unregister` when the login item is registered or waits for approval.
  /// A failure is logged and never thrown, so a reset still goes on.
  @discardableResult
  static func perform(
    status: SMAppService.Status = SMAppService.mainApp.status,
    unregister: () throws -> Void = { try SMAppService.mainApp.unregister() }
  ) -> Bool {
    guard LoginItemState(from: status).isOn else { return false }
    do {
      try unregister()
      return true
    } catch {
      Logger.app.error(
        "Could not turn off Start at Login: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }
}
