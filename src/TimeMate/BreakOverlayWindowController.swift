//  Created by homielab.com

import AppKit
import Combine
import SwiftUI

class BreakOverlayWindow: NSWindow {
  override var canBecomeKey: Bool {
    return true
  }
}

class BreakOverlayWindowController: NSObject {
  private var windows: [NSWindow] = []
  private var timer: PomodoroTimer
  private var cancellables = Set<AnyCancellable>()
  private var eventMonitor: Any?
  private var lastEscPressTime: Date?

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
    timer.$state.combineLatest(timer.$currentSessionType)
      .sink { [weak self] state, sessionType in
        self?.handleStateChange(state: state, sessionType: sessionType)
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
          self.timer.skipSession()
          self.lastEscPressTime = nil
        } else {
          self.lastEscPressTime = now
        }
        return nil  // Consume event
      }
      return event
    }
  }

  private func handleStateChange(state: PomodoroState, sessionType: SessionType) {
    let isBreak = sessionType == .shortBreak || sessionType == .longBreak
    let shouldShow = state == .active && isBreak

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

    // If already visible, do nothing (or update alpha)
    if windows.first?.isVisible == true && windows.first?.alphaValue == 1 { return }

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

    if animated {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 1.5
        windowsToClose.forEach { $0.animator().alphaValue = 0 }
      } completionHandler: { [weak self] in
        // Ensure we are on main thread and self exists
        DispatchQueue.main.async {
          windowsToClose.forEach { $0.close() }
          self?.windows.removeAll(where: { windowsToClose.contains($0) })
        }
      }
    } else {
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
