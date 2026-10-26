//  Created by homielab.com

import ServiceManagement
import XCTest

@testable import TimeMate

final class LoginItemStateTests: XCTestCase {
  func testEnabledIsOnWithoutApproval() {
    let state = LoginItemState(from: .enabled)
    XCTAssertTrue(state.isOn)
    XCTAssertFalse(state.needsApproval)
  }

  func testRequiresApprovalIsOnAndNeedsApproval() {
    let state = LoginItemState(from: .requiresApproval)
    XCTAssertTrue(state.isOn)
    XCTAssertTrue(state.needsApproval)
  }

  func testNotRegisteredAndNotFoundAreOff() {
    for status in [SMAppService.Status.notRegistered, .notFound] {
      let state = LoginItemState(from: status)
      XCTAssertFalse(state.isOn)
      XCTAssertFalse(state.needsApproval)
    }
  }
}
