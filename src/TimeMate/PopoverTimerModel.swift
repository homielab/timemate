//  Created by homielab.com

import Combine
import Foundation

/// What the popover shows of the timer, mirrored from `PomodoroTimer` so that
/// most of the popover doesn't re-render on every tick.
///
/// The slow-changing parts (state, session type, completed sessions) are
/// published here and only change when they really change. The per-second
/// countdown lives in `countdown`, observed only by the views that draw it, and
/// it is fed only while the popover is open.
final class PopoverTimerModel: ObservableObject {
  @Published private(set) var state: PomodoroState
  @Published private(set) var currentSessionType: SessionType
  @Published private(set) var focusSessionsCompleted: Int
  @Published private(set) var isBreakPostponed: Bool
  /// Mirrors `PomodoroTimer.canExtend`: "+5 min" is disabled at the 180-minute limit.
  @Published private(set) var canExtend: Bool

  /// Why "+5 min" is disabled: "Already at the 180-minute limit".
  var extendLimitText: String { TimerIntentActions.extendText(.atLimit) }
  /// A finished break waits on the break screen for "Continue Work".
  @Published private(set) var isWaitingToContinue: Bool

  /// The timer itself, for actions and the session history (not observed).
  let timer: PomodoroTimer
  let countdown: PopoverCountdown
  private var cancellables = Set<AnyCancellable>()

  init(timer: PomodoroTimer) {
    self.timer = timer
    state = timer.state
    currentSessionType = timer.currentSessionType
    focusSessionsCompleted = timer.focusSessionsCompleted
    isBreakPostponed = timer.isBreakPostponed
    isWaitingToContinue = timer.isWaitingToContinue
    canExtend = timer.canExtend
    countdown = PopoverCountdown(timer: timer)

    timer.$state.removeDuplicates()
      .sink { [weak self] in self?.state = $0 }
      .store(in: &cancellables)
    timer.$currentSessionType.removeDuplicates()
      .sink { [weak self] in self?.currentSessionType = $0 }
      .store(in: &cancellables)
    timer.$focusSessionsCompleted.removeDuplicates()
      .sink { [weak self] in self?.focusSessionsCompleted = $0 }
      .store(in: &cancellables)
    timer.$isBreakPostponed.removeDuplicates()
      .sink { [weak self] in self?.isBreakPostponed = $0 }
      .store(in: &cancellables)
    timer.$isWaitingToContinue.removeDuplicates()
      .sink { [weak self] in self?.isWaitingToContinue = $0 }
      .store(in: &cancellables)
    timer.$canExtend.removeDuplicates()
      .sink { [weak self] in self?.canExtend = $0 }
      .store(in: &cancellables)
  }

  /// What the big button under the countdown does right now.
  var mainAction: PopoverMainAction {
    PopoverMainAction(state: state, isWaitingToContinue: isWaitingToContinue)
  }

  /// Runs the big button: a finished break waiting on the break screen moves
  /// on to focus instead of running the break again.
  func performMainAction() {
    switch mainAction {
    case .start, .resume: timer.startTimer()
    case .pause: timer.pauseTimer()
    case .continueWork: timer.continueWork()
    }
  }

  /// Called when the popover opens or closes.
  func setPopoverVisible(_ visible: Bool) {
    countdown.setLive(visible)
  }
}

/// The popover's main button: Start, Pause, Resume or Continue Work.
enum PopoverMainAction: Equatable {
  case start, pause, resume, continueWork

  init(state: PomodoroState, isWaitingToContinue: Bool) {
    if isWaitingToContinue {
      self = .continueWork
      return
    }
    switch state {
    case .active: self = .pause
    case .paused: self = .resume
    case .idle: self = .start
    }
  }
}

/// The ticking part of the popover: remaining seconds and ring progress.
final class PopoverCountdown: ObservableObject {
  @Published private(set) var timeRemaining: Int
  @Published private(set) var progress: Double

  private let timer: PomodoroTimer
  private var subscription: AnyCancellable?

  /// Whether the countdown follows the timer (the popover is open).
  var isLive: Bool { subscription != nil }

  init(timer: PomodoroTimer) {
    self.timer = timer
    timeRemaining = timer.timeRemaining
    progress = timer.progress
  }

  /// Follows the timer while `live`; when it goes live again it catches up at
  /// once, since @Published replays the timer's current values.
  func setLive(_ live: Bool) {
    guard live != isLive else { return }
    guard live else {
      subscription = nil
      return
    }
    subscription = timer.$timeRemaining.combineLatest(timer.$progress)
      .sink { [weak self] timeRemaining, progress in
        guard let self else { return }
        if self.timeRemaining != timeRemaining { self.timeRemaining = timeRemaining }
        if self.progress != progress { self.progress = progress }
      }
  }
}
