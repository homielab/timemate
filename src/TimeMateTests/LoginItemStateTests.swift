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

final class LoginItemResetTests: XCTestCase {
  private struct Failure: Error {}

  func testUnregistersWhenEnabledOrAwaitingApproval() {
    for status in [SMAppService.Status.enabled, .requiresApproval] {
      var calls = 0
      XCTAssertTrue(LoginItemReset.perform(status: status, unregister: { calls += 1 }))
      XCTAssertEqual(calls, 1)
    }
  }

  func testLeavesAnUnregisteredLoginItemAlone() {
    for status in [SMAppService.Status.notRegistered, .notFound] {
      var calls = 0
      XCTAssertFalse(LoginItemReset.perform(status: status, unregister: { calls += 1 }))
      XCTAssertEqual(calls, 0)
    }
  }

  func testUnregisterFailureDoesNotThrow() {
    XCTAssertFalse(LoginItemReset.perform(status: .enabled, unregister: { throw Failure() }))
  }
}
