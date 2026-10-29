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
  /// The relaxation tip of the current break, shared by the windows on every screen.
  @Published private(set) var tip: String
  /// Today's progress ("Today: 3/8 pomodoros · 75 min" and the streak), as in the popover;
  /// nil before the first pomodoro of the day, so the line is hidden.
  @Published private(set) var today: TodaySummary?

  let timer: PomodoroTimer
  let countdown: BreakOverlayCountdown
  private let nextTip: () -> String
  private let defaults: UserDefaults
  private var cancellables = Set<AnyCancellable>()

  init(
    timer: PomodoroTimer,
    defaults: UserDefaults = .standard,
    now: @escaping () -> Date = Date.init,
    tip: @escaping () -> String = RelaxationTips.random
  ) {
    self.timer = timer
    self.nextTip = tip
    self.defaults = defaults
    self.tip = tip()
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

  /// Picks the tip for a break screen that is about to appear. Rebuilding the windows
  /// (a display change) must not call this, so the tip stays the same for the whole break.
  func chooseTip() {
    tip = nextTip()
  }

  /// One line: today's text, then the streak when it shows.
  static func todayText(_ summary: TodaySummary) -> String {
    summary.streakText.isEmpty
      ? summary.visibleText : "\(summary.visibleText) · \(summary.streakText)"
  }

  /// Reads today's progress from the history for a break screen that is about to appear.
  func refreshToday() {
    let history = timer.history
    let totals = history.todayTotals()
    guard totals.pomodoros > 0 else {
      today = nil
      return
    }
    let storedGoal = defaults.object(forKey: SettingsKey.dailyGoal) as? Int
    today = TodaySummary(
      pomodoros: totals.pomodoros, minutes: totals.focusMinutes, goal: storedGoal,
      streak: { history.goalStreak(goal: DailyGoal.sanitized(storedGoal)) })
  }

  /// Starts the countdown for a break screen that has just appeared: the skip delay
  /// starts over. Rebuilding the windows (a display change) must not call this.
  func beginBreakScreen() {
    countdown.resetSkipCountdown()
    countdown.setLive(true)
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
  /// Seconds between wall-clock ticks, or nil while the clock is stopped.
  var clockInterval: TimeInterval? { clock?.interval }

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
      format: NSLocalizedString("Skip available in %d s", comment: ""),
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

  /// Follows the timer while the break screen is up. Calling it again with the same value
  /// does nothing, and turning it back on keeps the skip delay where it was.
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

    timerSubscription = timer.$timeRemaining
      .sink { [weak self] remaining in
        guard let self else { return }
        if self.timeRemaining != remaining {
          // Only a second counting down is a tick: '+5 min' raises the time left and must not
          // shorten the skip delay.
          let isCountingDown = remaining < self.timeRemaining
          self.timeRemaining = remaining
          self.currentTime = self.now()
          let isBreakActive =
            self.timer.state == .active && self.timer.isBreak && !self.timer.isBreakPostponed
          if isBreakActive && isCountingDown {
            _ = self.skipCountdown.tick()
          }
        }
      }

    stateSubscription = timer.$state.combineLatest(timer.$isWaitingToContinue)
      .removeDuplicates(by: ==)
      .sink { [weak self] state, waiting in
        self?.updateClock(for: state, isWaitingToContinue: waiting)
      }
  }

  /// The wall clock drives the countdown only when the timer is not active (waiting to
  /// continue, paused). An active timer already publishes every second, so a second clock
  /// would wake the Mac twice a second. Waiting to continue ticks once a minute. The values
  /// are passed in because `@Published` fires before the new value is stored.
  private func updateClock(for state: PomodoroState, isWaitingToContinue: Bool) {
    guard isLive, state != .active else {
      stopClock()
      return
    }
    let interval = BreakOverlayMotion.clockInterval(isWaitingToContinue: isWaitingToContinue)
    if let clock, clock.interval == interval { return }
    stopClock()
    let overlayClock = OverlayClock()
    clockCancellable = overlayClock.$now.dropFirst().sink { [weak self] date in
      guard let self else { return }
      if self.timer.state != .active {
        self.currentTime = date
      }
    }
    overlayClock.start(interval: interval)
    clock = overlayClock
    currentTime = now()
  }

  private func stopClock() {
    clock?.stop()
    clock = nil
    clockCancellable = nil
  }
}
