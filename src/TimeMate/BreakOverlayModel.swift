//  Created by homielab.com

import Combine
import Foundation

/// State mirrored from `PomodoroTimer` for the break overlay so that most of the
/// overlay (blur, dimming, Lottie cat, tip) does not re-render on each 1-second tick.
///
/// Slow-changing state (`state`, `currentSessionType`, `isWaitingToContinue`, `isBreakPostponed`)
/// is published here with deduplication. Per-second updates (countdown text and skip delay)
/// live in `countdown`, observed only by the views that draw them.
final class BreakOverlayModel: ObservableObject {
  @Published private(set) var state: PomodoroState
  @Published private(set) var currentSessionType: SessionType
  @Published private(set) var isWaitingToContinue: Bool
  @Published private(set) var isBreakPostponed: Bool

  let timer: PomodoroTimer
  let countdown: BreakOverlayCountdown
  private var cancellables = Set<AnyCancellable>()

  init(
    timer: PomodoroTimer,
    defaults: UserDefaults = .standard,
    now: @escaping () -> Date = Date.init
  ) {
    self.timer = timer
    self.state = timer.state
    self.currentSessionType = timer.currentSessionType
    self.isWaitingToContinue = timer.isWaitingToContinue
    self.isBreakPostponed = timer.isBreakPostponed
    self.countdown = BreakOverlayCountdown(timer: timer, defaults: defaults, now: now)

    timer.$state.removeDuplicates()
      .sink { [weak self] in self?.state = $0 }
      .store(in: &cancellables)
    timer.$currentSessionType.removeDuplicates()
      .sink { [weak self] in self?.currentSessionType = $0 }
      .store(in: &cancellables)
    timer.$isWaitingToContinue.removeDuplicates()
      .sink { [weak self] in self?.isWaitingToContinue = $0 }
      .store(in: &cancellables)
    timer.$isBreakPostponed.removeDuplicates()
      .sink { [weak self] in self?.isBreakPostponed = $0 }
      .store(in: &cancellables)
  }

  func setLive(_ live: Bool) {
    countdown.setLive(live)
  }

  func extendBreak(by minutes: Int = BreakOverlayAccessibility.extendMinutes) {
    timer.extend(by: minutes)
  }

  func postponeBreak(minutes: Int) {
    timer.postponeBreak(minutes: minutes)
  }

  func skipSession() {
    timer.skipSession()
  }

  func continueWork() {
    timer.continueWork()
  }
}

/// The ticking part of the break overlay: time remaining string, clock time, and skip countdown.
final class BreakOverlayCountdown: ObservableObject {
  @Published private(set) var timeRemaining: Int
  @Published private(set) var currentTime: Date
  @Published private(set) var skipCountdown: BreakSkipCountdown

  private let timer: PomodoroTimer
  private let defaults: UserDefaults
  private let now: () -> Date
  private var timerSubscription: AnyCancellable?
  private var stateSubscription: AnyCancellable?
  private var clock: OverlayClock?
  private var clockCancellable: AnyCancellable?

  var isLive: Bool { timerSubscription != nil }
  var isClockRunning: Bool { clock?.isRunning ?? false }

  var canSkip: Bool { skipCountdown.canSkip }
  var skipSecondsRemaining: Int { skipCountdown.remainingSeconds }

  var timeRemainingString: String {
    timeRemaining.toMinuteSecondString()
  }

  var countdownValue: String {
    BreakOverlayAccessibility.countdownValue(secondsRemaining: timeRemaining)
  }

  var skipAvailableText: String {
    String(
      format: NSLocalizedString("Skip available in %d", comment: ""),
      skipCountdown.remainingSeconds)
  }

  init(
    timer: PomodoroTimer,
    defaults: UserDefaults = .standard,
    now: @escaping () -> Date = Date.init
  ) {
    self.timer = timer
    self.defaults = defaults
    self.now = now
    self.timeRemaining = timer.timeRemaining
    self.currentTime = now()
    let storedDelay = defaults.object(forKey: SettingsKey.overlaySkipDelay)
    let delay = BreakOverlayAccessibility.skipDelay(stored: storedDelay)
    self.skipCountdown = BreakSkipCountdown(skipDelay: delay)
  }

  func resetSkipCountdown(skipDelay: Int? = nil) {
    let delay: Int
    if let skipDelay {
      delay = BreakOverlayAccessibility.skipDelay(stored: skipDelay)
    } else {
      let storedDelay = defaults.object(forKey: SettingsKey.overlaySkipDelay)
      delay = BreakOverlayAccessibility.skipDelay(stored: storedDelay)
    }
    skipCountdown.reset(skipDelay: delay)
  }

  func setLive(_ live: Bool) {
    guard live != isLive else { return }
    guard live else {
      timerSubscription = nil
      stateSubscription = nil
      stopClock()
      return
    }

    // Catch up immediately
    timeRemaining = timer.timeRemaining
    currentTime = now()
    resetSkipCountdown()

    timerSubscription = timer.$timeRemaining
      .sink { [weak self] remaining in
        guard let self else { return }
        if self.timeRemaining != remaining {
          self.timeRemaining = remaining
          self.currentTime = self.now()
          let isBreakActive =
            self.timer.state == .active && self.timer.isBreak && !self.timer.isBreakPostponed
          if isBreakActive {
            _ = self.skipCountdown.tick()
          }
        }
      }

    stateSubscription = timer.$state.removeDuplicates()
      .sink { [weak self] state in self?.updateClock(for: state) }
    updateClock(for: timer.state)
  }

  /// The wall clock drives the countdown only when the timer is not active (waiting to
  /// continue, paused). An active timer already publishes every second, so a second clock
  /// would wake the Mac twice a second. `state` is passed in because `$state` fires before
  /// the new value is stored.
  private func updateClock(for state: PomodoroState) {
    guard isLive, state != .active else {
      stopClock()
      return
    }
    guard clock == nil else { return }
    let overlayClock = OverlayClock()
    clockCancellable = overlayClock.$now.dropFirst().sink { [weak self] date in
      guard let self else { return }
      if self.timer.state != .active {
        self.currentTime = date
      }
    }
    overlayClock.start()
    clock = overlayClock
  }

  private func stopClock() {
    clock?.stop()
    clock = nil
    clockCancellable = nil
  }
}
