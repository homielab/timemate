//  Created by homielab.com

import AppKit
import Combine
import CoreGraphics

/// Whether the break screen may take over the display right now.
///
/// The break screen activates the app and covers everything, which would throw a
/// presentation or a video call out of full screen. With "Don't interrupt full-screen
/// apps" on, it waits until the app in front leaves full screen (or the break ends); with
/// "Wait during calls and video" on, it also waits while another app keeps the display
/// awake (a call, screen sharing, a video in a normal window).
///
/// The settings the break screen reacts to. Compared on every defaults change so that
/// unrelated writes (timer snapshot, volume, colors) don't re-evaluate the overlay.
struct OverlaySettings: Equatable {
  var enabled: Bool
  var skipFullscreen: Bool
  var waitDuringCalls: Bool

  init(enabled: Bool, skipFullscreen: Bool, waitDuringCalls: Bool = false) {
    self.enabled = enabled
    self.skipFullscreen = skipFullscreen
    self.waitDuringCalls = waitDuringCalls
  }

  init(defaults: UserDefaults) {
    self.init(
      enabled: defaults.bool(forKey: SettingsKey.overlayEnabled),
      skipFullscreen: defaults.bool(forKey: SettingsKey.overlaySkipFullscreen),
      waitDuringCalls: defaults.bool(forKey: SettingsKey.overlayWaitDuringCalls))
  }
}

enum OverlayPolicy {
  enum Presentation: Equatable {
    /// Show the break screen.
    case show
    /// The break screen is due but an app is in full screen (or, with "Wait during calls
    /// and video", keeps the display awake): keep checking.
    case waitForWindowedApp
    /// No break screen.
    case hide
  }

  /// Whether the break screen can appear at all right now. Each probe runs only when
  /// the answer depends on it.
  static func breakScreenCanShow(
    settings: OverlaySettings, isFrontmostFullscreen: () -> Bool,
    otherAppKeepsDisplayAwake: () -> Bool
  ) -> Bool {
    settings.enabled && !(settings.skipFullscreen && isFrontmostFullscreen())
      && !(settings.waitDuringCalls && otherAppKeepsDisplayAwake())
  }

  /// While the break screen waits for the frontmost app to leave full screen, it looks
  /// again when the active Space or the app in front changes, and shortly after a click.
  /// This slow poll only catches what those miss (full screen left by
  /// keyboard without a Space change).
  static let fallbackPollInterval: TimeInterval = 30

  /// A Space change is posted when the full-screen animation starts, while the app's
  /// full-screen window may still be listed. Each change (and each click while waiting:
  /// leaving full screen inside the same app, e.g. a video, comes with a click) is
  /// checked again this long after, once the animation has settled.
  static let settleRecheckDelay: TimeInterval = 1.5

  /// Clicks while waiting schedule at most one settle re-check per this interval.
  static let clickRecheckMinInterval: TimeInterval = 1

  /// - Parameters:
  ///   - shouldShow: the break screen is due (`BreakOverlayRules.shouldShowOverlay`);
  ///     false once the break is over, skipped or postponed.
  ///   - skipFullscreen: the "Don't interrupt full-screen apps" setting.
  ///   - isFrontmostFullscreen: the app in front covers a whole screen.
  ///   - waitDuringCalls: the "Wait during calls and video" setting.
  ///   - otherAppKeepsDisplayAwake: another app holds a display-awake assertion
  ///     (`DisplayAwakeProbe.isKeptAwakeByOtherApp`).
  ///   - isVisible: the break screen is already on screen; it stays.
  static func presentation(
    shouldShow: Bool, skipFullscreen: Bool, isFrontmostFullscreen: Bool,
    waitDuringCalls: Bool = false, otherAppKeepsDisplayAwake: Bool = false,
    isVisible: Bool = false
  ) -> Presentation {
    guard shouldShow else { return .hide }
    guard !isVisible else { return .show }
    if skipFullscreen && isFrontmostFullscreen { return .waitForWindowedApp }
    if waitDuringCalls && otherAppKeepsDisplayAwake { return .waitForWindowedApp }
    return .show
  }

  /// Whether a window of `windowSizes` fills a screen of `screenSizes` (a maximized window
  /// stays below the menu bar and doesn't count).
  static func isFullscreen(windowSizes: [CGSize], screenSizes: [CGSize]) -> Bool {
    windowSizes.contains { window in
      screenSizes.contains { screen in
        window.width >= screen.width - 1 && window.height >= screen.height - 1
      }
    }
  }

  /// Whether the app in front (not TimeMate) has a window that fills a screen.
  /// Limits: it can't tell that the screen is being shared or recorded, only that the app
  /// in front is full screen; a Zoom call in a normal window is caught only by
  /// "Wait during calls and video" (`DisplayAwakeProbe`).
  static func isFrontmostAppFullscreen() -> Bool {
    guard let app = NSWorkspace.shared.frontmostApplication,
      app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return false }
    let sizes: [CGSize] = windows.compactMap { info in
      guard (info[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
        (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
        let bounds = info[kCGWindowBounds as String] as? NSDictionary,
        let rect = CGRect(dictionaryRepresentation: bounds)
      else { return nil }
      return rect.size
    }
    return isFullscreen(windowSizes: sizes, screenSizes: NSScreen.screens.map(\.frame.size))
  }
}

/// A wall clock that runs only between `start(interval:)` and `stop()`, so a hidden
/// break screen costs nothing. Ticks land on whole multiples of `interval`.
final class OverlayClock: ObservableObject {
  @Published private(set) var now = Date()
  private var timer: Timer?
  private(set) var interval: TimeInterval = 1
  var isRunning: Bool { timer != nil }

  func start(interval: TimeInterval = 1) {
    guard timer == nil else { return }
    self.interval = interval
    now = Date()
    let timer = Timer(
      fire: BreakOverlayMotion.nextTick(after: now, interval: interval), interval: interval,
      repeats: true
    ) { [weak self] _ in self?.now = Date() }
    timer.tolerance = interval > 1 ? 1 : TickMode.tolerance
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  deinit { timer?.invalidate() }
}
