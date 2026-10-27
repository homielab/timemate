//  Created by homielab.com

import Combine
import Foundation

/// What the menu bar item shows of the timer, mirrored from `PomodoroTimer`.
///
/// The timer publishes `timeRemaining` and `progress` one after the other on
/// every tick, and @Published announces a change even when the value is the
/// same, so observing the timer redraws the menu bar twice a second. Here each
/// value is published only when it really changes: a tick changes at most
/// `timeRemaining`, and the menu bar doesn't use `progress` at all.
final class MenuBarModel: ObservableObject {
  @Published private(set) var state: PomodoroState
  @Published private(set) var currentSessionType: SessionType
  @Published private(set) var timeRemaining: Int
  /// Read by the VoiceOver label only.
  @Published private(set) var isBreakPostponed: Bool
  /// Read by the VoiceOver label only.
  @Published private(set) var isWaitingToContinue: Bool

  private var cancellables = Set<AnyCancellable>()

  init(timer: PomodoroTimer) {
    state = timer.state
    currentSessionType = timer.currentSessionType
    timeRemaining = timer.timeRemaining
    isBreakPostponed = timer.isBreakPostponed
    isWaitingToContinue = timer.isWaitingToContinue

    timer.$state.removeDuplicates()
      .sink { [weak self] in self?.state = $0 }
      .store(in: &cancellables)
    timer.$currentSessionType.removeDuplicates()
      .sink { [weak self] in self?.currentSessionType = $0 }
      .store(in: &cancellables)
    timer.$timeRemaining.removeDuplicates()
      .sink { [weak self] in self?.timeRemaining = $0 }
      .store(in: &cancellables)
    timer.$isBreakPostponed.removeDuplicates()
      .sink { [weak self] in self?.isBreakPostponed = $0 }
      .store(in: &cancellables)
    timer.$isWaitingToContinue.removeDuplicates()
      .sink { [weak self] in self?.isWaitingToContinue = $0 }
      .store(in: &cancellables)
  }

  /// What VoiceOver reads for the status item, e.g. "TimeMate, Focus,
  /// 12 minutes, 34 seconds remaining".
  var accessibilityLabel: String {
    StatusItemMenu.accessibilityLabel(
      sessionType: currentSessionType, state: state, secondsRemaining: timeRemaining,
      isBreakPostponed: isBreakPostponed, isWaitingToContinue: isWaitingToContinue)
  }
}
