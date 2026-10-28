//  Created by homielab.com

import SwiftUI
import XCTest

@testable import TimeMate

final class PopoverMotionTests: XCTestCase {
  private let kinds: [PopoverMotion.Kind] = [.progress, .settingsChevron, .longBreak]

  func testReduceMotionTurnsEveryAnimationOff() {
    for kind in kinds {
      XCTAssertNil(PopoverMotion.animation(kind, reduceMotion: true), "\(kind)")
    }
  }

  func testAnimationsAreUnchangedWithoutReduceMotion() {
    XCTAssertEqual(PopoverMotion.animation(.progress, reduceMotion: false), .linear)
    XCTAssertEqual(
      PopoverMotion.animation(.settingsChevron, reduceMotion: false), .easeInOut(duration: 0.3))
    XCTAssertEqual(
      PopoverMotion.animation(.longBreak, reduceMotion: false), .easeInOut(duration: 0.2))
  }
}
