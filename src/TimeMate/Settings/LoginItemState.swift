//  Created by homielab.com

import ServiceManagement

/// What the Start at Login toggle shows for a login item registration status.
struct LoginItemState: Equatable {
  let isOn: Bool
  let needsApproval: Bool

  init(from status: SMAppService.Status) {
    isOn = (status == .enabled || status == .requiresApproval)
    needsApproval = (status == .requiresApproval)
  }
}
