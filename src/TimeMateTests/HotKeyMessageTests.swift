import UserNotifications
import XCTest

@testable import TimeMate

final class HotKeyMessageTests: XCTestCase {
  private var posted: [UNNotificationRequest] = []
  private var beeps = 0
  private var announced: [String] = []

  private func makeMessage(enabled: Bool, authorized: Bool) -> HotKeyMessage {
    HotKeyMessage(
      notificationsEnabled: { enabled },
      checkAuthorized: { $0(authorized) },
      post: { self.posted.append($0) },
      beep: { self.beeps += 1 },
      announce: { self.announced.append($0) })
  }

  func testNotificationsOffBeepsWithoutBanner() {
    makeMessage(enabled: false, authorized: true).show("Limit")
    XCTAssertTrue(posted.isEmpty)
    XCTAssertEqual(beeps, 1)
    XCTAssertEqual(announced, ["Limit"])
  }

  func testDeniedByMacOSBeeps() {
    makeMessage(enabled: true, authorized: false).show("Limit")
    XCTAssertTrue(posted.isEmpty)
    XCTAssertEqual(beeps, 1)
    XCTAssertEqual(announced, ["Limit"])
  }

  func testAllowedPostsBanner() {
    makeMessage(enabled: true, authorized: true).show("Limit")
    XCTAssertEqual(posted.map(\.content.body), ["Limit"])
    XCTAssertEqual(posted.first?.identifier, HotKeyMessage.identifier)
    XCTAssertEqual(beeps, 0)
    XCTAssertEqual(announced, ["Limit"])
  }
}
