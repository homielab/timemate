//  Created by homielab.com

import SwiftUI
import XCTest

@testable import TimeMate

final class MenuBarLayoutTests: XCTestCase {
  func testWidthWithAndWithoutTime() {
    XCTAssertEqual(MenuBarLayout.width(hideTime: true), 24)
    XCTAssertEqual(MenuBarLayout.width(hideTime: false), 90)
    XCTAssertEqual(MenuBarView.width(hideTime: true), 24)
    XCTAssertEqual(MenuBarView.width(hideTime: false), 90)
  }

  func testIconNameForStates() {
    XCTAssertEqual(
      MenuBarLayout.iconName(state: .paused, sessionType: .focus), "pause.circle.fill")
    XCTAssertEqual(
      MenuBarLayout.iconName(state: .paused, sessionType: .shortBreak), "pause.circle.fill")
    XCTAssertEqual(MenuBarLayout.iconName(state: .idle, sessionType: .focus), "timer")
    XCTAssertEqual(MenuBarLayout.iconName(state: .idle, sessionType: .shortBreak), "timer")
    XCTAssertEqual(
      MenuBarLayout.iconName(state: .active, sessionType: .focus), "play.circle.fill")
    XCTAssertEqual(
      MenuBarLayout.iconName(state: .active, sessionType: .shortBreak),
      SessionType.shortBreak.style.iconName)
    XCTAssertEqual(
      MenuBarLayout.iconName(state: .active, sessionType: .longBreak),
      SessionType.longBreak.style.iconName)
  }

  func testColorsForStates() {
    XCTAssertEqual(MenuBarLayout.accentColor(state: .paused, sessionType: .focus), .orange)
    XCTAssertEqual(
      MenuBarLayout.accentColor(state: .active, sessionType: .focus), SessionType.focus.style.color)
    XCTAssertEqual(
      MenuBarLayout.accentColor(state: .active, sessionType: .shortBreak),
      SessionType.shortBreak.style.color.opacity(0.8))
    XCTAssertEqual(
      MenuBarLayout.accentColor(state: .active, sessionType: .longBreak),
      SessionType.longBreak.style.color.opacity(0.8))

    XCTAssertEqual(MenuBarLayout.foregroundColor(state: .active), .white)
    XCTAssertEqual(
      MenuBarLayout.foregroundColor(state: .idle), Color(nsColor: .headerTextColor))
    XCTAssertEqual(
      MenuBarLayout.foregroundColor(state: .paused), Color(nsColor: .headerTextColor))
  }
}
