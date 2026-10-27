//  Created by homielab.com

import AppKit
import XCTest

@testable import TimeMate

final class LaunchBehaviorTests: XCTestCase {
  private func openEvent(asLoginItem: Bool) -> NSAppleEventDescriptor {
    let event = NSAppleEventDescriptor(
      eventClass: kCoreEventClass, eventID: kAEOpenApplication, targetDescriptor: nil,
      returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
    )
    if asLoginItem {
      event.setParam(
        NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
    }
    return event
  }

  func testFirstLaunchShowsThePopoverEvenAtLogin() {
    XCTAssertTrue(
      LaunchBehavior.showsPopover(isFirstLaunch: true, isLoginLaunch: true, showTimerAtLogin: false)
    )
  }

  func testLaunchAtLoginStaysQuietByDefault() {
    XCTAssertFalse(
      LaunchBehavior.showsPopover(
        isFirstLaunch: false, isLoginLaunch: true, showTimerAtLogin: false))
  }

  func testLaunchAtLoginShowsThePopoverWhenAskedTo() {
    XCTAssertTrue(
      LaunchBehavior.showsPopover(isFirstLaunch: false, isLoginLaunch: true, showTimerAtLogin: true)
    )
  }

  func testLaunchByHandShowsThePopover() {
    XCTAssertTrue(
      LaunchBehavior.showsPopover(
        isFirstLaunch: false, isLoginLaunch: false, showTimerAtLogin: false))
  }

  func testLoginItemOpenEventIsALoginLaunch() {
    XCTAssertTrue(LaunchBehavior.isLoginLaunch(openEvent(asLoginItem: true)))
  }

  func testPlainOpenEventIsNotALoginLaunch() {
    XCTAssertFalse(LaunchBehavior.isLoginLaunch(openEvent(asLoginItem: false)))
    XCTAssertFalse(LaunchBehavior.isLoginLaunch(nil))
  }

  func testOtherEventsAreNotALoginLaunch() {
    let reopen = NSAppleEventDescriptor(
      eventClass: kCoreEventClass, eventID: kAEReopenApplication, targetDescriptor: nil,
      returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
    )
    reopen.setParam(
      NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
    XCTAssertFalse(LaunchBehavior.isLoginLaunch(reopen))
  }

  func testAutoStartOnLaunchOnlyStartsAnIdleFocusSession() {
    func start(
      _ enabled: Bool = true, _ state: PomodoroState = .idle, _ type: SessionType = .focus,
      waiting: Bool = false
    ) -> Bool {
      LaunchBehavior.shouldAutoStartOnLaunch(
        enabled: enabled, state: state, sessionType: type, isWaiting: waiting)
    }
    XCTAssertTrue(start())
    XCTAssertFalse(start(false))
    XCTAssertFalse(start(true, .idle, .shortBreak))
    XCTAssertFalse(start(true, .idle, .longBreak))
    XCTAssertFalse(start(true, .idle, .focus, waiting: true))
    XCTAssertFalse(start(true, .active))
    XCTAssertFalse(start(true, .paused))
  }
}
