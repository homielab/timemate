//  Created by homielab.com

import AppKit
import Combine
import SwiftUI

class BreakOverlayWindow: NSWindow {
  override var canBecomeKey: Bool {
    return true
  }
}

/// Tracks the overlay's fade-outs with a generation counter. The windows are
/// closed when a fade-out ends, but only if nothing showed or hid the overlay in
/// the meantime, so showing it again during the fade-out cancels the close.
struct OverlayVisibilityGeneration {
  private(set) var current = 0
  /// Whether a fade-out is running whose close has not been cancelled.
  private(set) var isClosePending = false

  /// Starts a fade-out and returns the token its close must present.
  mutating func beginHide() -> Int {
    current += 1
    isClosePending = true
    return current
  }

  /// Shows the overlay, cancelling any pending close. Returns whether one was
  /// cancelled (the windows are fading out and must be faded back in).
  mutating func beginShow() -> Bool {
    current += 1
    defer { isClosePending = false }
    return isClosePending
  }

  /// Whether the fade-out that got `token` may close the windows now.
  mutating func shouldClose(_ token: Int) -> Bool {
    guard token == current, isClosePending else { return false }
    isClosePending = false
    return true
  }
}

class BreakOverlayWindowController: NSObject {
  private var windows: [NSWindow] = []
  /// The window on the screen the user works on: it gets focus and the animation.
  private var primaryWindow: NSWindow?
  private var timer: PomodoroTimer
  private var cancellables = Set<AnyCancellable>()
  private var eventMonitor: Any?
  private var escDetector = DoubleEscDetector()
  private var visibilityGeneration = OverlayVisibilityGeneration()

  init(timer: PomodoroTimer) {
    self.timer = timer
    super.init()
    setupSubscriptions()
    setupEventMonitor()

    // Listen for screen changes
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleScreenConfigurationChange),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
  }

  @objc private func handleScreenConfigurationChange() {
    // Re-create windows when screens change
    if !windows.isEmpty {
      let isVisible = windows.first?.isVisible ?? false

      closeAllWindows()

      if isVisible {
        createWindows()
        showWindows(animated: false)  // Snap to new layout
      }
    }
  }

  private func createWindows() {
    closeAllWindows()  // Clear existing

    let screens = NSScreen.screens
    let primaryIndex = BreakOverlayAccessibility.primaryScreenIndex(
      screens: screens.map(\.frame), main: NSScreen.main?.frame)

    for (index, screen) in screens.enumerated() {
      let isPrimary = index == primaryIndex
      let window = BreakOverlayWindow(
        contentRect: screen.frame,
        styleMask: [.borderless, .fullSizeContentView],
        backing: .buffered,
        defer: false,
        screen: screen
      )

      // Force frame to match screen exactly to ensure it appears on the correct display
      window.setFrame(screen.frame, display: true)

      window.level = .mainMenu + 1  // Cover menu bar and dock
      window.backgroundColor = .clear
      window.isOpaque = false
      window.hasShadow = false
      window.ignoresMouseEvents = false
      window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      window.isReleasedWhenClosed = false

      let contentView = BreakOverlayView(timer: timer, isPrimary: isPrimary)
      window.contentView = NSHostingView(rootView: contentView)

      windows.append(window)
      if isPrimary {
        primaryWindow = window
      }
    }
  }

  private func closeAllWindows() {
    windows.forEach { $0.close() }
    windows.removeAll()
    primaryWindow = nil
  }

  private func setupSubscriptions() {
    timer.$state.combineLatest(
      timer.$currentSessionType, timer.$isWaitingToContinue, timer.$isBreakPostponed
    )
    .sink { [weak self] state, sessionType, isWaiting, isPostponed in
      self?.handleStateChange(
        state: state, sessionType: sessionType, isWaitingToContinue: isWaiting,
        isBreakPostponed: isPostponed)
    }
    .store(in: &cancellables)
  }

  private func setupEventMonitor() {
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self = self else { return event }

      // Check if any overlay window is visible
      let isOverlayVisible = self.windows.contains { $0.isVisible }
      guard isOverlayVisible else { return event }

      if event.keyCode == DoubleEscDetector.escKeyCode {
        if self.escDetector.registerPress() {
          switch BreakOverlayRules.escAction(isWaitingToContinue: self.timer.isWaitingToContinue) {
          case .continueWork: self.timer.continueWork()
          case .skipSession: self.timer.skipSession()
          }
        }
        return nil  // Consume event
      }
      return event
    }
  }

  private func handleStateChange(
    state: PomodoroState, sessionType: SessionType, isWaitingToContinue: Bool,
    isBreakPostponed: Bool
  ) {
    let shouldShow = BreakOverlayRules.shouldShowOverlay(
      state: state, sessionType: sessionType, isWaiting: isWaitingToContinue,
      isPostponed: isBreakPostponed,
      enabled: UserDefaults.standard.bool(forKey: SettingsKey.overlayEnabled))

    if shouldShow {
      // Not when the overlay only comes back during its fade-out.
      let isNewlyShown = windows.isEmpty
      if windows.isEmpty {
        createWindows()
      }
      showWindows(animated: true)
      if isNewlyShown && !isWaitingToContinue {
        announceBreakStart()
      }
    } else {
      hideWindows(animated: true)
    }
  }

  private func showWindows(animated: Bool) {
    guard !windows.isEmpty else { return }

    // Cancels the close of a fade-out still in progress.
    let wasFadingOut = visibilityGeneration.beginShow()

    // If already visible, do nothing (or update alpha)
    if !wasFadingOut && windows.first?.isVisible == true && windows.first?.alphaValue == 1 {
      return
    }

    let fadeDuration =
      animated
      ? BreakOverlayAccessibility.fadeDuration(
        reduceMotion: BreakOverlayAccessibility.reduceMotion) : nil

    // Activate once so the overlay receives key events (Esc), then give focus
    // to the window on the screen the user works on.
    NSApp.activate(ignoringOtherApps: true)
    for window in windows where window !== primaryWindow {
      window.alphaValue = fadeDuration == nil ? 1 : 0
      window.orderFront(nil)
    }
    if let primaryWindow {
      primaryWindow.alphaValue = fadeDuration == nil ? 1 : 0
      primaryWindow.makeKeyAndOrderFront(nil)
    }

    if let fadeDuration {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = fadeDuration
        for window in windows {
          window.animator().alphaValue = 1
        }
      }
    }
  }

  private func announceBreakStart() {
    // The session type changes before the timer resets to the break length, so
    // read the remaining time once the current change has finished.
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.windows.isEmpty, !self.visibilityGeneration.isClosePending else {
        return
      }
      self.postAnnouncement()
    }
  }

  private func postAnnouncement() {
    let text = BreakOverlayAccessibility.announcement(secondsRemaining: timer.timeRemaining)
    NSAccessibility.post(
      element: primaryWindow ?? NSApp as Any,
      notification: .announcementRequested,
      userInfo: [
        .announcement: text,
        .priority: NSAccessibilityPriorityLevel.high.rawValue,
      ])
  }

  private func hideWindows(animated: Bool) {
    guard !windows.isEmpty else { return }

    let windowsToClose = windows  // Capture current windows
    let token = visibilityGeneration.beginHide()

    let fadeDuration =
      animated
      ? BreakOverlayAccessibility.fadeDuration(
        reduceMotion: BreakOverlayAccessibility.reduceMotion) : nil

    if let fadeDuration {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = fadeDuration
        windowsToClose.forEach { $0.animator().alphaValue = 0 }
      } completionHandler: { [weak self] in
        // Ensure we are on main thread and self exists
        DispatchQueue.main.async {
          // The overlay was shown again during the fade-out: keep it.
          guard let self, self.visibilityGeneration.shouldClose(token) else { return }
          windowsToClose.forEach { $0.close() }
          self.windows.removeAll(where: { windowsToClose.contains($0) })
          if let primary = self.primaryWindow, windowsToClose.contains(primary) {
            self.primaryWindow = nil
          }
        }
      }
    } else {
      _ = visibilityGeneration.shouldClose(token)
      windowsToClose.forEach { $0.close() }
      windows.removeAll()
      primaryWindow = nil
    }
  }

  deinit {
    if let monitor = eventMonitor {
      NSEvent.removeMonitor(monitor)
    }
    NotificationCenter.default.removeObserver(self)
  }
}
