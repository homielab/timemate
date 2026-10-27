//  Created by homielab.com

import AppKit
import SwiftUI

/// Layout and appearance decisions for the menu bar item.
enum MenuBarLayout {
  static func width(style: MenuBarTimeStyle) -> CGFloat {
    switch style {
    case .minutesSeconds: return 90
    case .minutesOnly: return 64
    case .iconOnly: return 24
    }
  }

  static func iconName(state: PomodoroState, sessionType: SessionType) -> String {
    switch state {
    case .paused:
      return "pause.circle.fill"
    case .idle:
      return "timer"
    case .active:
      return sessionType == .focus
        ? "play.circle.fill" : sessionType.style.iconName
    }
  }

  static func accentColor(state: PomodoroState, sessionType: SessionType) -> Color {
    if state == .paused {
      return .orange
    }
    let activeColor = sessionType.style.color

    if sessionType == .shortBreak || sessionType == .longBreak {
      return activeColor.opacity(0.8)
    }
    return activeColor
  }

  static func foregroundColor(state: PomodoroState) -> Color {
    if state == .active {
      return .white
    }
    return Color(nsColor: .headerTextColor)
  }
}

// MARK: - Pass-through hosting view for menu bar (allows clicks to reach NSStatusBarButton)
// NOTE: Using AnyView instead of a generic parameter to work around a Swift 6.2 compiler crash
// in the SIL optimizer (EarlyPerfInliner) when processing the deinit of generic NSHostingView subclasses.
class PassThroughHostingView: NSHostingView<AnyView> {
  override func hitTest(_ point: NSPoint) -> NSView? {
    // Return nil so that clicks pass through to the underlying NSStatusBarButton
    return nil
  }
}

struct MenuBarView: View {
  /// Not the timer itself: that would redraw the menu bar twice every tick.
  @ObservedObject var model: MenuBarModel
  let style: MenuBarTimeStyle

  static func width(style: MenuBarTimeStyle) -> CGFloat {
    MenuBarLayout.width(style: style)
  }

  private var iconName: String {
    MenuBarLayout.iconName(state: model.state, sessionType: model.currentSessionType)
  }

  private var accentColor: Color {
    MenuBarLayout.accentColor(state: model.state, sessionType: model.currentSessionType)
  }

  private var foregroundColor: Color {
    MenuBarLayout.foregroundColor(state: model.state)
  }

  var body: some View {
    // The status item button carries the VoiceOver label (time included), so
    // its drawing stays out of the accessibility tree.
    HStack(spacing: 4) {
      Image(systemName: iconName)
        .font(.system(size: NSFont.systemFontSize + 2))
        .padding(.horizontal, 4)
        .background(
          RoundedRectangle(cornerRadius: 4)
            .fill(model.state == .active ? accentColor : .clear)
        )
        .foregroundColor(model.state == .active ? .white : Color(nsColor: .headerTextColor))

      if style.showsTime {
        Text(style.text(seconds: model.timeRemaining))
          .font(.system(size: NSFont.systemFontSize + 1, design: .monospaced).weight(.bold))
          .foregroundColor(foregroundColor)
      }
    }
    .frame(
      width: MenuBarLayout.width(style: style), height: NSStatusBar.system.thickness,
      alignment: .center
    )
    .accessibilityHidden(true)
  }
}
