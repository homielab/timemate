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
  private let timer: PomodoroTimer
  let defaults: UserDefaults
  let animated: Bool
  let model: BreakOverlayModel
  private var cancellables = Set<AnyCancellable>()
  private var defaultsObserver: DefaultsObserver?
  private var eventMonitor: Any?
  private var screenObserver: NSObjectProtocol?
  /// Re-checks whether the frontmost app left full screen while the break screen waits.
  private var fullscreenPoll: Timer?
  private var lastState: (PomodoroState, SessionType, Bool, Bool)?
  /// The two settings the break screen depends on, as of the last evaluation.
  private var lastSettings: OverlaySettings?
  /// Whether the app in front is full screen; replaced in tests to count the (costly) lookups.
  let isFullscreenProbe: () -> Bool
  /// How many times the break screen's visibility was evaluated (for tests).
  private(set) var evaluationCount = 0
  private var escDetector = DoubleEscDetector()
  private var visibilityGeneration = OverlayVisibilityGeneration()

  var isShowingOverlay: Bool {
    !windows.isEmpty && !visibilityGeneration.isClosePending
  }

  init(
    timer: PomodoroTimer,
    defaults: UserDefaults = .standard,
    animated: Bool = true,
    isFullscreenProbe: @escaping () -> Bool = OverlayPolicy.isFrontmostAppFullscreen
  ) {
    self.isFullscreenProbe = isFullscreenProbe
    self.timer = timer
    self.defaults = defaults
    self.animated = animated
    self.model = BreakOverlayModel(timer: timer, defaults: defaults)
    super.init()
    setupSubscriptions()
  }

  /// Listens for screen changes and Esc only while the break screen exists.
  private func startObserving() {
    if screenObserver == nil {
      screenObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.handleScreenConfigurationChange() }
    }
    setupEventMonitor()
  }

  private func stopObserving() {
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    screenObserver = nil
    if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
    eventMonitor = nil
  }

  /// Re-creates the windows for the new screen layout. A break screen that is fading out
  /// is left to close: rebuilding it would cancel the close and bring it back. The
  /// countdown keeps running across the rebuild.
  private func handleScreenConfigurationChange() {
    guard isShowingOverlay, windows.first?.isVisible == true else { return }
    createWindows()
    showWindows(animated: false)  // Snap to new layout
  }

  private func createWindows() {
    closeAllWindows()  // Clear existing
    startObserving()

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

      let contentView = BreakOverlayView(model: model, isPrimary: isPrimary)
      window.contentView = NSHostingView(rootView: contentView)

      windows.append(window)
      if isPrimary {
        primaryWindow = window
      }
    }
  }

  private func closeAllWindows() {
    for window in windows { window.close() }
    windows.removeAll()
    primaryWindow = nil
    stopObserving()
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

    defaultsObserver = DefaultsObserver(
      defaults: defaults, keys: [SettingsKey.overlayEnabled, SettingsKey.overlaySkipFullscreen]
    ) { [weak self] in self?.handleDefaultsChange() }
  }

  private func handleDefaultsChange() {
    // Every defaults write (timer snapshot, volume, colors...) lands here; only the
    // break screen's own settings matter.
    guard OverlaySettings(defaults: defaults) != lastSettings else { return }
    guard let state = lastState else {
      handleStateChange(
        state: timer.state,
        sessionType: timer.currentSessionType,
        isWaitingToContinue: timer.isWaitingToContinue,
        isBreakPostponed: timer.isBreakPostponed)
      return
    }
    handleStateChange(
      state: state.0, sessionType: state.1, isWaitingToContinue: state.2,
      isBreakPostponed: state.3)
  }

  private func setupEventMonitor() {
    guard eventMonitor == nil else { return }
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self = self else { return event }

      // Check if any overlay window is visible
      let isOverlayVisible = self.windows.contains { $0.isVisible }
      guard isOverlayVisible else { return event }

      if event.keyCode == DoubleEscDetector.escKeyCode {
        if self.escDetector.registerPress() {
          switch BreakOverlayRules.escAction(
            isWaitingToContinue: self.timer.isWaitingToContinue,
            canSkip: self.model.countdown.canSkip)
          {
          case .continueWork: self.timer.continueWork()
          case .skipSession: self.timer.skipSession()
          case .none: break
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
    evaluationCount += 1
    let wasWaiting = lastState?.2 ?? isWaitingToContinue
    lastState = (state, sessionType, isWaitingToContinue, isBreakPostponed)
    let settings = OverlaySettings(defaults: defaults)
    lastSettings = settings
    let shouldShow = BreakOverlayRules.shouldShowOverlay(
      state: state, sessionType: sessionType, isWaiting: isWaitingToContinue,
      isPostponed: isBreakPostponed, enabled: settings.enabled)

    let isVisible = windows.contains { $0.isVisible }
    let presentation = OverlayPolicy.presentation(
      shouldShow: shouldShow,
      skipFullscreen: settings.skipFullscreen,
      // The window list is only read when the answer can matter.
      isFrontmostFullscreen: shouldShow && settings.skipFullscreen && !isVisible
        && isFullscreenProbe(),
      isVisible: isVisible)

    if presentation == .waitForWindowedApp {
      startFullscreenPoll()
      return
    }
    stopFullscreenPoll()

    if presentation == .show {
      // Not when the overlay only comes back during its fade-out.
      let isNewlyShown = windows.isEmpty
      if windows.isEmpty {
        createWindows()
        startBreakCountdown()
      }
      showWindows(animated: animated)
      if isNewlyShown && !isWaitingToContinue {
        announceBreakStart()
      } else if BreakOverlayAccessibility.announcesBreakEnd(
        wasWaiting: wasWaiting, isWaiting: isWaitingToContinue, isNewlyShown: isNewlyShown)
      {
        postAnnouncement(BreakOverlayAccessibility.endAnnouncement())
      }
    } else {
      hideWindows(animated: animated)
    }
  }

  /// The notification already told the user the session ended; the break screen comes
  /// once the app in front leaves full screen, until the break is over.
  private func startFullscreenPoll() {
    guard fullscreenPoll == nil else { return }
    fullscreenPoll = Timer.scheduledTimer(
      withTimeInterval: OverlayPolicy.pollInterval, repeats: true
    ) { [weak self] _ in
      guard let self, let state = self.lastState else { return }
      self.handleStateChange(
        state: state.0, sessionType: state.1, isWaitingToContinue: state.2,
        isBreakPostponed: state.3)
    }
    fullscreenPoll?.tolerance = TickMode.tolerance
  }

  private func stopFullscreenPoll() {
    fullscreenPoll?.invalidate()
    fullscreenPoll = nil
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

  /// Starts the skip delay of a break screen that has just appeared. The session type
  /// changes before the timer resets to the break length, so wait for the current change
  /// to finish: that reset must not count as a second of the delay.
  private func startBreakCountdown() {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.isShowingOverlay else { return }
      self.model.beginBreakScreen()
    }
  }

  private func announceBreakStart() {
    // The session type changes before the timer resets to the break length, so
    // read the remaining time once the current change has finished.
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.windows.isEmpty, !self.visibilityGeneration.isClosePending else {
        return
      }
      self.postAnnouncement(
        BreakOverlayAccessibility.announcement(secondsRemaining: self.timer.timeRemaining))
    }
  }

  private func postAnnouncement(_ text: String) {
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
        for window in windowsToClose { window.animator().alphaValue = 0 }
      } completionHandler: { [weak self] in
        // Ensure we are on main thread and self exists
        DispatchQueue.main.async {
          // The overlay was shown again during the fade-out: keep it.
          guard let self, self.visibilityGeneration.shouldClose(token) else { return }
          for window in windowsToClose { window.close() }
          self.windows.removeAll(where: { windowsToClose.contains($0) })
          if let primary = self.primaryWindow, windowsToClose.contains(primary) {
            self.primaryWindow = nil
          }
          if self.windows.isEmpty {
            self.stopObserving()
            self.model.setLive(false)
          }
        }
      }
    } else {
      _ = visibilityGeneration.shouldClose(token)
      for window in windowsToClose { window.close() }
      windows.removeAll()
      primaryWindow = nil
      stopObserving()
      model.setLive(false)
    }
  }

  deinit {
    stopFullscreenPoll()
    stopObserving()
  }
}
