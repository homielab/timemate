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
  private var timer: PomodoroTimer
  private var cancellables = Set<AnyCancellable>()
  private var eventMonitor: Any?
  private var lastEscPressTime: Date?
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

    for screen in NSScreen.screens {
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

      let contentView = BreakOverlayView(timer: timer)
      window.contentView = NSHostingView(rootView: contentView)

      windows.append(window)
    }
  }

  private func closeAllWindows() {
    windows.forEach { $0.close() }
    windows.removeAll()
  }

  private func setupSubscriptions() {
    timer.$state.combineLatest(timer.$currentSessionType, timer.$isWaitingToContinue)
      .sink { [weak self] state, sessionType, isWaiting in
        self?.handleStateChange(state: state, sessionType: sessionType, isWaitingToContinue: isWaiting)
      }
      .store(in: &cancellables)
  }

  private func setupEventMonitor() {
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self = self else { return event }

      // Check if any overlay window is visible
      let isOverlayVisible = self.windows.contains { $0.isVisible }
      guard isOverlayVisible else { return event }

      if event.keyCode == 53 {  // Esc key
        let now = Date()
        if let lastPress = self.lastEscPressTime, now.timeIntervalSince(lastPress) < 0.5 {
          // Double press detected
          if self.timer.isWaitingToContinue {
            self.timer.continueWork()
          } else {
            self.timer.skipSession()
          }
          self.lastEscPressTime = nil
        } else {
          self.lastEscPressTime = now
        }
        return nil  // Consume event
      }
      return event
    }
  }

  private func handleStateChange(state: PomodoroState, sessionType: SessionType, isWaitingToContinue: Bool) {
    let isBreak = sessionType == .shortBreak || sessionType == .longBreak
    let shouldShow = (state == .active && isBreak) || isWaitingToContinue

    // Check user setting
    let overlayEnabled = UserDefaults.standard.bool(forKey: "overlayEnabled")

    if shouldShow && overlayEnabled {
      if windows.isEmpty {
        createWindows()
      }
      showWindows(animated: true)
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

    for window in windows {
      window.alphaValue = 0
      window.makeKeyAndOrderFront(nil)

      // Ensure app is active to receive key events
      NSApp.activate(ignoringOtherApps: true)

      if animated {
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 1.5
          window.animator().alphaValue = 1
        }
      } else {
        window.alphaValue = 1
      }
    }
  }

  private func hideWindows(animated: Bool) {
    guard !windows.isEmpty else { return }

    let windowsToClose = windows  // Capture current windows
    let token = visibilityGeneration.beginHide()

    if animated {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 1.5
        windowsToClose.forEach { $0.animator().alphaValue = 0 }
      } completionHandler: { [weak self] in
        // Ensure we are on main thread and self exists
        DispatchQueue.main.async {
          // The overlay was shown again during the fade-out: keep it.
          guard let self, self.visibilityGeneration.shouldClose(token) else { return }
          windowsToClose.forEach { $0.close() }
          self.windows.removeAll(where: { windowsToClose.contains($0) })
        }
      }
    } else {
      _ = visibilityGeneration.shouldClose(token)
      windowsToClose.forEach { $0.close() }
      windows.removeAll()
    }
  }

  deinit {
    if let monitor = eventMonitor {
      NSEvent.removeMonitor(monitor)
    }
    NotificationCenter.default.removeObserver(self)
  }
}
