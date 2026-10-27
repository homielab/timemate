//  Created by homielab.com

import Combine
import Lottie
import SwiftUI

struct VisualEffectBlur: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.blendingMode = .behindWindow
    view.state = .active
    view.material = .hudWindow
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct BreakOverlayView: View {
  @ObservedObject var model: BreakOverlayModel
  /// Only the overlay on the main screen plays the animation.
  let isPrimary: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isAnimating = false
  @State private var currentTip = ""

  init(model: BreakOverlayModel, isPrimary: Bool) {
    self.model = model
    self.isPrimary = isPrimary
  }

  init(timer: PomodoroTimer, isPrimary: Bool) {
    self.init(model: BreakOverlayModel(timer: timer), isPrimary: isPrimary)
  }

  /// The entrance animation, or none when Reduce Motion is on.
  private func entrance(_ duration: Double, delay: Double = 0) -> Animation? {
    reduceMotion ? nil : .easeOut(duration: duration).delay(delay)
  }

  var body: some View {
    ZStack {
      VisualEffectBlur()
        .edgesIgnoringSafeArea(.all)

      Color.black.opacity(0.4)
        .edgesIgnoringSafeArea(.all)

      VStack(spacing: 40) {
        // Top: Current Time (observes countdown only)
        BreakOverlayTimeView(
          countdown: model.countdown,
          isAnimating: isAnimating,
          entrance: entrance(1.0)
        )

        Spacer()

        // Center: Image, Relaxation Tip & Timer
        VStack(spacing: 30) {
          if isPrimary {
            Group {
              if reduceMotion {
                LottieView(animation: .named("cat-playing"))
                  .paused(at: .progress(0.5))
              } else {
                LottieView(animation: .named("cat-playing"))
                  .playing(loopMode: .loop)
              }
            }
            .frame(width: 535, height: 228)
            .opacity(isAnimating ? 1 : 0)
            .scaleEffect(isAnimating || reduceMotion ? 1 : 0.9)
            .animation(entrance(1.5), value: isAnimating)
            .accessibilityHidden(true)
          }

          VStack(spacing: 10) {
            Text(LocalizedStringKey(currentTip))
              .font(.system(size: 32, weight: .light))
              .multilineTextAlignment(.center)
              .foregroundColor(.white.opacity(0.9))
              .padding(.horizontal, 40)
              .opacity(isAnimating ? 1 : 0)
              .offset(y: isAnimating || reduceMotion ? 0 : 20)
              .animation(entrance(1.0, delay: 0.3), value: isAnimating)
          }

          // Center countdown text (observes countdown only)
          BreakOverlayCountdownTextView(
            countdown: model.countdown,
            isAnimating: isAnimating,
            entrance: entrance(1.0, delay: 0.9)
          )
        }

        Spacer()

        // Bottom: Break actions & Hint
        BreakOverlayBottomActionsView(
          model: model,
          countdown: model.countdown,
          reduceMotion: reduceMotion,
          isAnimating: isAnimating,
          entrance: entrance(1.0, delay: 1.2)
        )
      }
    }
    .onAppear {
      model.setLive(true)
      isAnimating = true
      currentTip = RelaxationTips.random()
    }
    .onTapGesture {
      if model.isWaitingToContinue {
        model.continueWork()
      }
    }
    .onDisappear {
      model.setLive(false)
    }
  }
}

// MARK: - Subviews that isolate 1-second ticks

private struct BreakOverlayTimeView: View {
  @ObservedObject var countdown: BreakOverlayCountdown
  let isAnimating: Bool
  let entrance: Animation?

  var body: some View {
    Text(countdown.currentTime, style: .time)
      .font(.system(size: 24, weight: .medium, design: .monospaced))
      .foregroundColor(.white.opacity(0.6))
      .padding(.top, 60)
      .opacity(isAnimating ? 1 : 0)
      .animation(entrance, value: isAnimating)
  }
}

private struct BreakOverlayCountdownTextView: View {
  @ObservedObject var countdown: BreakOverlayCountdown
  let isAnimating: Bool
  let entrance: Animation?

  var body: some View {
    Text(countdown.timeRemainingString)
      .font(.system(size: 120, weight: .bold, design: .monospaced))
      .foregroundColor(.white)
      .padding(.top, 20)
      .opacity(isAnimating ? 1 : 0)
      .animation(entrance, value: isAnimating)
      .accessibilityLabel(Text(LocalizedStringKey("Break time remaining")))
      .accessibilityValue(Text(countdown.countdownValue))
  }
}

private struct BreakOverlayBottomActionsView: View {
  @Environment(\.colorSchemeContrast) private var contrast
  private var hintOpacity: Double {
    BreakOverlayAccessibility.hintOpacity(increaseContrast: contrast == .increased)
  }
  @ObservedObject var model: BreakOverlayModel
  @ObservedObject var countdown: BreakOverlayCountdown
  let reduceMotion: Bool
  let isAnimating: Bool
  let entrance: Animation?

  private func outlinedCapsule(_ label: Text, compact: Bool = false) -> some View {
    label
      .font(compact ? .subheadline.weight(.semibold) : .headline)
      .foregroundColor(.white)
      .padding(.horizontal, compact ? 16 : 30)
      .padding(.vertical, compact ? 8 : 12)
      .background(
        Capsule()
          .fill(Color.white.opacity(0.1))
      )
      .overlay(
        Capsule()
          .strokeBorder(Color.white, lineWidth: compact ? 1 : 2)
      )
      .contentShape(Capsule())
  }

  private var extendButton: some View {
    Button(action: {
      model.extendBreak(by: BreakOverlayAccessibility.extendMinutes)
    }) {
      outlinedCapsule(Text(LocalizedStringKey("+5 min")))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(LocalizedStringKey("Add 5 minutes to the break")))
  }

  private var postponeButtons: some View {
    HStack(spacing: 8) {
      Text(LocalizedStringKey("Postpone"))
        .font(.subheadline)
        .foregroundColor(.white.opacity(hintOpacity))
        .accessibilityHidden(true)
      ForEach(BreakOverlayAccessibility.postponeOptions, id: \.self) { minutes in
        Button(action: {
          model.postponeBreak(minutes: minutes)
        }) {
          outlinedCapsule(
            Text(String(format: NSLocalizedString("%d min", comment: ""), minutes)), compact: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(BreakOverlayAccessibility.postponeLabel(minutes: minutes)))
      }
    }
  }

  var body: some View {
    VStack(spacing: 16) {
      HStack(spacing: 16) {
        if model.isWaitingToContinue {
          Button(action: {
            model.continueWork()
          }) {
            Text(LocalizedStringKey("Continue Work"))
              .font(.headline)
              .foregroundColor(.black)
              .padding(.horizontal, 40)
              .padding(.vertical, 14)
              .background(
                Capsule()
                  .fill(Color.white)
              )
              .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .accessibilityHint(Text(LocalizedStringKey("Press Esc twice or click to continue")))
          .transition(.opacity)
          extendButton
        } else {
          extendButton
          if countdown.canSkip {
            postponeButtons
              .transition(.opacity)
            Button(action: {
              model.skipSession()
            }) {
              outlinedCapsule(Text(LocalizedStringKey("Skip Break")))
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(LocalizedStringKey("Press Esc twice to skip")))
            .transition(.opacity)
          } else {
            Text(countdown.skipAvailableText)
              .font(.body)
              .foregroundColor(.white.opacity(hintOpacity))
              .padding(.vertical, 12)
          }
        }
      }

      if model.isWaitingToContinue {
        Text(LocalizedStringKey("Press Esc twice or click to continue"))
          .font(.caption)
          .foregroundColor(.white.opacity(hintOpacity))
          .padding(.top, 8)
      } else {
        Text(LocalizedStringKey("Press Esc twice to skip"))
          .font(.caption)
          .foregroundColor(.white.opacity(hintOpacity))
          .padding(.top, 8)
      }
    }
    .padding(.bottom, 60)
    .frame(height: 120)
    .opacity(isAnimating ? 1 : 0)
    .animation(entrance, value: isAnimating)
  }
}
