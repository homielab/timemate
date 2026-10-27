//  Created by homielab.com

import AppKit
import Combine
import CoreGraphics

/// Whether the break screen may take over the display right now.
///
/// The break screen activates the app and covers everything, which would throw a
/// presentation or a video call out of full screen. With "Don't interrupt full-screen
/// apps" on, it waits until the app in front leaves full screen (or the break ends).
/// The settings the break screen reacts to. Compared on every defaults change so that
/// unrelated writes (timer snapshot, volume, colors) don't re-evaluate the overlay.
struct OverlaySettings: Equatable {
  var enabled: Bool
  var skipFullscreen: Bool

  init(enabled: Bool, skipFullscreen: Bool) {
    self.enabled = enabled
    self.skipFullscreen = skipFullscreen
  }

  init(defaults: UserDefaults) {
    self.init(
      enabled: defaults.bool(forKey: SettingsKey.overlayEnabled),
      skipFullscreen: defaults.bool(forKey: SettingsKey.overlaySkipFullscreen))
  }
}

enum OverlayPolicy {
  enum Presentation: Equatable {
    /// Show the break screen.
    case show
    /// The break screen is due but an app is in full screen: keep checking.
    case waitForWindowedApp
    /// No break screen.
    case hide
  }

  /// Whether the break screen can appear at all right now. The probe runs only when
  /// the answer depends on it.
  static func breakScreenCanShow(
    settings: OverlaySettings, isFrontmostFullscreen: () -> Bool
  ) -> Bool {
    settings.enabled && !(settings.skipFullscreen && isFrontmostFullscreen())
  }

  /// How often to look again while waiting for the frontmost app to leave full screen.
  static let pollInterval: TimeInterval = 5

  /// - Parameters:
  ///   - shouldShow: the break screen is due (`BreakOverlayRules.shouldShowOverlay`);
  ///     false once the break is over, skipped or postponed.
  ///   - skipFullscreen: the "Don't interrupt full-screen apps" setting.
  ///   - isFrontmostFullscreen: the app in front covers a whole screen.
  ///   - isVisible: the break screen is already on screen; it stays.
  static func presentation(
    shouldShow: Bool, skipFullscreen: Bool, isFrontmostFullscreen: Bool, isVisible: Bool = false
  ) -> Presentation {
    guard shouldShow else { return .hide }
    if skipFullscreen && isFrontmostFullscreen && !isVisible { return .waitForWindowedApp }
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
  /// in front is full screen; a Zoom call in a normal window is not detected.
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

/// A once-a-second clock that runs only between `start()` and `stop()`, so a hidden
/// break screen costs nothing.
final class OverlayClock: ObservableObject {
  @Published private(set) var now = Date()
  private var timer: Timer?
  var isRunning: Bool { timer != nil }

  func start() {
    guard timer == nil else { return }
    now = Date()
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.now = Date() }
    timer.tolerance = TickMode.tolerance
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  deinit { timer?.invalidate() }
}
