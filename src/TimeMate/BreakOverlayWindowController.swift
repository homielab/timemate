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
  /// While the break screen waits for the frontmost app to leave full screen: the
  /// Space and app-switch observers, a click monitor, a settle re-check and a slow
  /// fallback poll.
  private let workspaceNotificationCenter: NotificationCenter
  private let fallbackPollInterval: TimeInterval?
  private let settleDelay: TimeInterval?
  /// Runs a settle re-check after a delay; replaced in tests to run it on demand.
  typealias RecheckScheduler = (_ delay: TimeInterval, _ work: DispatchWorkItem) -> Void
  private let scheduleRecheck: RecheckScheduler
  private var frontmostAppObservers: [NSObjectProtocol] = []
  private var fullscreenPoll: Timer?
  private var settleRecheck: DispatchWorkItem?
  /// Screen changes arrive in bursts (dock, KVM): rebuild once they settle.
  static let screenChangeDelay: TimeInterval = 0.5
  private let screenChangeDelayValue: TimeInterval?
  private var pendingScreenRebuild: DispatchWorkItem?
  private var clickMonitor: Any?
  private var lastClickRecheck: Date?
  /// Whether a re-check is scheduled for when a full-screen animation has settled.
  var hasPendingSettleRecheck: Bool { settleRecheck != nil }
  /// Whether the slow fallback poll is running (only while waiting, if an interval is set).
  var hasFallbackPoll: Bool { fullscreenPoll != nil }
  /// Whether clicks in other apps are watched (only while waiting).
  var isMonitoringClicks: Bool { clickMonitor != nil }
  /// Whether the break screen is waiting for the frontmost app to leave full screen, or
  /// for a call or video to end.
  var isWaitingForWindowedApp: Bool { !frontmostAppObservers.isEmpty }
  private var lastState: (PomodoroState, SessionType, Bool, Bool)?
  /// The settings the break screen depends on, as of the last evaluation.
  private var lastSettings: OverlaySettings?
  /// Whether the app in front is full screen; replaced in tests to count the (costly) lookups.
  let isFullscreenProbe: () -> Bool
  /// Whether another app keeps the display awake (a call, screen sharing, a video); read
  /// only with "Wait during calls and video" on. Replaced in tests.
  let isDisplayKeptAwakeProbe: () -> Bool
  /// How many times the break screen's visibility was evaluated (for tests).
  private(set) var evaluationCount = 0
  /// Fades windows to an opacity over a duration, then calls back. Replaced in tests:
  /// window animations only run while the screen is unlocked.
  typealias FadeRunner =
    (
      _ windows: [NSWindow], _ alpha: CGFloat, _ duration: TimeInterval,
      _ done: @escaping () -> Void
    )
    -> Void
  private let runFade: FadeRunner
  private var escDetector = DoubleEscDetector()
  private var visibilityGeneration = OverlayVisibilityGeneration()

  var isShowingOverlay: Bool {
    !windows.isEmpty && !visibilityGeneration.isClosePending
  }

  /// The tip each break window shows, one per screen.
  var windowTips: [String] {
    windows.compactMap { ($0.contentView as? NSHostingView<BreakOverlayView>)?.rootView.model.tip }
  }

  /// Whether each break window skips the entrance animation (true after a screen change).
  var windowSkipsEntrance: [Bool] {
    windows.compactMap {
      ($0.contentView as? NSHostingView<BreakOverlayView>)?.rootView.skipsEntrance
    }
  }

  /// The titles of the break screen windows, one per screen.
  var windowTitles: [String] { windows.map(\.title) }

  init(
    timer: PomodoroTimer,
    defaults: UserDefaults = .standard,
    animated: Bool = true,
    isFullscreenProbe: @escaping () -> Bool = OverlayPolicy.isFrontmostAppFullscreen,
    isDisplayKeptAwakeProbe: @escaping () -> Bool = DisplayAwakeProbe.isKeptAwakeByOtherApp,
    workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    fallbackPollInterval: TimeInterval? = OverlayPolicy.fallbackPollInterval,
    settleDelay: TimeInterval? = OverlayPolicy.settleRecheckDelay,
    scheduleRecheck: @escaping RecheckScheduler = BreakOverlayWindowController.scheduleOnMain,
    runFade: @escaping FadeRunner = BreakOverlayWindowController.animateFade,
    screenChangeDelay: TimeInterval? = BreakOverlayWindowController.screenChangeDelay,
    tip: @escaping () -> String = RelaxationTips.random
  ) {
    self.isFullscreenProbe = isFullscreenProbe
    self.isDisplayKeptAwakeProbe = isDisplayKeptAwakeProbe
    self.workspaceNotificationCenter = workspaceNotificationCenter
    self.fallbackPollInterval = fallbackPollInterval
    self.settleDelay = settleDelay
    self.scheduleRecheck = scheduleRecheck
    self.runFade = runFade
    self.screenChangeDelayValue = screenChangeDelay
    self.timer = timer
    self.defaults = defaults
    self.animated = animated
    self.model = BreakOverlayModel(timer: timer, defaults: defaults, tip: tip)
    super.init()
    timer.breakScreenSkipLock = { [weak self] in
      guard let self, self.isShowingOverlay, !self.model.countdown.canSkip else { return 0 }
      return self.model.countdown.skipSecondsRemaining
    }
    setupSubscriptions()
  }

  /// Runs the work on the main queue after the delay.
  static func scheduleOnMain(after delay: TimeInterval, _ work: DispatchWorkItem) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  /// Animates the windows' opacity with `NSAnimationContext`.
  static func animateFade(
    _ windows: [NSWindow], to alpha: CGFloat, duration: TimeInterval,
    done: @escaping () -> Void
  ) {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      for window in windows { window.animator().alphaValue = alpha }
    } completionHandler: {
      done()
    }
  }

  /// Listens for screen changes and Esc only while the break screen exists.
  private func startObserving() {
    if screenObserver == nil {
      screenObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.scheduleScreenRebuild() }
    }
    setupEventMonitor()
  }

  private func stopObserving() {
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    screenObserver = nil
    pendingScreenRebuild?.cancel()
    pendingScreenRebuild = nil
    if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
    eventMonitor = nil
  }

  /// Re-creates the windows for the new screen layout. A break screen that is fading out
  /// is left to close: rebuilding it would cancel the close and bring it back. The
  /// countdown keeps running across the rebuild.
  private func scheduleScreenRebuild() {
    pendingScreenRebuild?.cancel()
    guard let delay = screenChangeDelayValue else {
      handleScreenConfigurationChange()
      return
    }
    let work = DispatchWorkItem { [weak self] in
      self?.pendingScreenRebuild = nil
      self?.handleScreenConfigurationChange()
    }
    pendingScreenRebuild = work
    scheduleRecheck(delay, work)
  }

  /// The rebuilt windows show the break as it is, without replaying the entrance.
  private func handleScreenConfigurationChange() {
    guard isShowingOverlay, windows.first?.isVisible == true else { return }
    createWindows(skipsEntrance: true)
    showWindows(animated: false)  // Snap to new layout
  }

  private func createWindows(skipsEntrance: Bool = false) {
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
      // Borderless windows show no title, but VoiceOver reads it to name the window.
      window.title = BreakOverlayAccessibility.windowTitle()

      let contentView = BreakOverlayView(
        model: model, isPrimary: isPrimary, skipsEntrance: skipsEntrance)
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
      defaults: defaults,
      keys: [
        SettingsKey.overlayEnabled, SettingsKey.overlaySkipFullscreen,
        SettingsKey.overlayWaitDuringCalls,
      ]
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
    let isFrontmostFullscreen =
      // The window list is only read when the answer can matter.
      shouldShow && settings.skipFullscreen && !isVisible && isFullscreenProbe()
    let presentation = OverlayPolicy.presentation(
      shouldShow: shouldShow,
      skipFullscreen: settings.skipFullscreen,
      isFrontmostFullscreen: isFrontmostFullscreen,
      waitDuringCalls: settings.waitDuringCalls,
      // Nor the power assertions when the full-screen check already decided.
      otherAppKeepsDisplayAwake: shouldShow && settings.waitDuringCalls && !isVisible
        && !isFrontmostFullscreen && isDisplayKeptAwakeProbe(),
      isVisible: isVisible)

    if presentation == .waitForWindowedApp {
      startWaitingForWindowedApp()
      return
    }
    stopWaitingForWindowedApp()

    if presentation == .show {
      // Not when the overlay only comes back during its fade-out.
      let isNewlyShown = windows.isEmpty
      if windows.isEmpty {
        model.chooseTip()
        model.refreshToday()
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
  /// once the app in front leaves full screen (or the call or video ends), until the
  /// break is over. Looks again when
  /// the active Space or the app in front changes, again `settleDelay` later (the
  /// Space change comes before the full-screen animation ends) and after a click, and
  /// every `fallbackPollInterval` for what those miss, instead of reading the window
  /// list every few seconds.
  private func startWaitingForWindowedApp() {
    if frontmostAppObservers.isEmpty {
      frontmostAppObservers = [
        NSWorkspace.activeSpaceDidChangeNotification,
        NSWorkspace.didActivateApplicationNotification,
      ].map { name in
        workspaceNotificationCenter.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] _ in self?.handleWorkspaceChangeWhileWaiting()
        }
      }
    }
    if clickMonitor == nil, settleDelay != nil {
      // Clicks in other apps need no permission; key presses would.
      clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
        [weak self] _ in self?.handleClickWhileWaiting()
      }
    }
    guard fullscreenPoll == nil, let fallbackPollInterval else { return }
    let poll = Timer(timeInterval: fallbackPollInterval, repeats: true) { [weak self] _ in
      self?.reevaluate()
    }
    poll.tolerance = fallbackPollInterval / 10
    RunLoop.main.add(poll, forMode: .common)
    fullscreenPoll = poll
  }

  private func stopWaitingForWindowedApp() {
    for observer in frontmostAppObservers {
      workspaceNotificationCenter.removeObserver(observer)
    }
    frontmostAppObservers = []
    fullscreenPoll?.invalidate()
    fullscreenPoll = nil
    settleRecheck?.cancel()
    settleRecheck = nil
    if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    clickMonitor = nil
    lastClickRecheck = nil
  }

  /// The Space or the app in front changed: look now, and again once the animation settled.
  private func handleWorkspaceChangeWhileWaiting() {
    reevaluate()
    guard isWaitingForWindowedApp else { return }
    scheduleSettleRecheck(replacingPending: true)
  }

  /// A click while waiting (leaving a video's full screen): look again shortly, at most
  /// once per `OverlayPolicy.clickRecheckMinInterval`.
  func handleClickWhileWaiting(now: Date = Date()) {
    guard isWaitingForWindowedApp else { return }
    if let lastClickRecheck,
      now.timeIntervalSince(lastClickRecheck) < OverlayPolicy.clickRecheckMinInterval
    {
      return
    }
    lastClickRecheck = now
    scheduleSettleRecheck(replacingPending: false)
  }

  /// One pending re-check at a time: events in a burst push it back (a workspace change)
  /// or join it (a click).
  private func scheduleSettleRecheck(replacingPending: Bool) {
    guard let settleDelay else { return }
    if settleRecheck != nil {
      guard replacingPending else { return }
      settleRecheck?.cancel()
    }
    let work = DispatchWorkItem { [weak self] in
      self?.settleRecheck = nil
      self?.reevaluate()
    }
    settleRecheck = work
    scheduleRecheck(settleDelay, work)
  }

  /// Evaluates the break screen again with the last known timer state.
  private func reevaluate() {
    guard let state = lastState else { return }
    handleStateChange(
      state: state.0, sessionType: state.1, isWaitingToContinue: state.2,
      isBreakPostponed: state.3)
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
      runFade(windows, 1, fadeDuration) {}
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
      runFade(windowsToClose, 0, fadeDuration) { [weak self] in
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
    stopWaitingForWindowedApp()
    stopObserving()
  }
}
