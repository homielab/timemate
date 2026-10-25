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
  @ObservedObject var timer: PomodoroTimer
  /// Only the overlay on the main screen plays the animation.
  let isPrimary: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var currentTime = Date()
  @State private var showSkipButton = false
  @State private var countdown = BreakOverlayAccessibility.defaultSkipDelay
  @State private var isAnimating = false
  @State private var currentTip = ""

  /// One clock shared by the overlays of all screens.
  private static let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  /// The entrance animation, or none when Reduce Motion is on.
  private func entrance(_ duration: Double, delay: Double = 0) -> Animation? {
    reduceMotion ? nil : .easeOut(duration: duration).delay(delay)
  }

  /// A white-outlined capsule, the look of the secondary break buttons.
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

  /// "+5 min": makes the break longer (or, once it ended, starts 5 more minutes).
  private var extendButton: some View {
    Button(action: {
      timer.extend(by: BreakOverlayAccessibility.extendMinutes)
    }) {
      outlinedCapsule(Text(LocalizedStringKey("+5 min")))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(LocalizedStringKey("Add 5 minutes to the break")))
  }

  /// "Postpone 1 / 3 / 5 min": hides the break screen and brings the break back later.
  private var postponeButtons: some View {
    HStack(spacing: 8) {
      Text(LocalizedStringKey("Postpone"))
        .font(.subheadline)
        .foregroundColor(.white.opacity(0.7))
        .accessibilityHidden(true)
      ForEach(BreakOverlayAccessibility.postponeOptions, id: \.self) { minutes in
        Button(action: {
          timer.postponeBreak(minutes: minutes)
        }) {
          outlinedCapsule(
            Text(String(format: NSLocalizedString("%d min", comment: ""), minutes)), compact: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(BreakOverlayAccessibility.postponeLabel(minutes: minutes)))
      }
    }
  }

  /// Seconds before Skip and Postpone show, from Settings.
  private var skipDelay: Int {
    BreakOverlayAccessibility.skipDelay(
      stored: UserDefaults.standard.object(forKey: SettingsKey.overlaySkipDelay))
  }

  /// Starts the wait before Skip shows; with no delay it shows right away.
  private func resetSkipCountdown() {
    countdown = skipDelay
    showSkipButton = countdown == 0
  }

  var body: some View {
    ZStack {
      VisualEffectBlur()
        .edgesIgnoringSafeArea(.all)

      Color.black.opacity(0.4)
        .edgesIgnoringSafeArea(.all)

      VStack(spacing: 40) {
        // Top: Current Time
        Text(currentTime, style: .time)
          .font(.system(size: 24, weight: .medium, design: .monospaced))
          .foregroundColor(.white.opacity(0.6))
          .padding(.top, 60)
          .opacity(isAnimating ? 1 : 0)
          .animation(entrance(1.0), value: isAnimating)

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

          Text(timer.timeRemaining.toMinuteSecondString())
            .font(.system(size: 120, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.top, 20)
            .opacity(isAnimating ? 1 : 0)
            .animation(entrance(1.0, delay: 0.9), value: isAnimating)
            .accessibilityLabel(Text(LocalizedStringKey("Break time remaining")))
            .accessibilityValue(
              Text(BreakOverlayAccessibility.countdownValue(secondsRemaining: timer.timeRemaining)))
        }

        Spacer()

        // Bottom: Break actions & Hint
        VStack(spacing: 16) {
          HStack(spacing: 16) {
            if timer.isWaitingToContinue {
              Button(action: {
                timer.continueWork()
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
              if showSkipButton {
                postponeButtons
                  .transition(.opacity)
                Button(action: {
                  timer.skipSession()
                }) {
                  outlinedCapsule(Text(LocalizedStringKey("Skip Break")))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(LocalizedStringKey("Press Esc twice to skip")))
                .transition(.opacity)
              } else {
                Text(
                  String(
                    format: NSLocalizedString("Skip available in %d", comment: ""), countdown)
                )
                .font(.body)
                .foregroundColor(.white.opacity(0.5))
                .padding(.vertical, 12)
              }
            }
          }

          if timer.isWaitingToContinue {
            Text(LocalizedStringKey("Press Esc twice or click to continue"))
              .font(.caption)
              .foregroundColor(.white.opacity(0.4))
              .padding(.top, 8)
          } else {
            Text(LocalizedStringKey("Press Esc twice to skip"))
              .font(.caption)
              .foregroundColor(.white.opacity(0.4))
              .padding(.top, 8)
          }
        }
        .padding(.bottom, 60)
        .frame(height: 120)
        .opacity(isAnimating ? 1 : 0)
        .animation(entrance(1.0, delay: 1.2), value: isAnimating)
      }
    }
    .onAppear {
      resetSkipCountdown()
      isAnimating = true
      currentTip = RelaxationTips.random()
    }
    .onTapGesture {
      if timer.isWaitingToContinue {
        timer.continueWork()
      }
    }
    .onReceive(Self.clock) { input in
      currentTime = input

      let isBreakActive = timer.state == .active && timer.isBreak && !timer.isBreakPostponed

      if isBreakActive || timer.isWaitingToContinue {
        if !isAnimating {
          isAnimating = true
          currentTip = RelaxationTips.random()
        }
        if countdown > 1 {
          countdown -= 1
        } else if !showSkipButton {
          countdown = 0
          withAnimation(reduceMotion ? nil : .default) {
            showSkipButton = true
          }
        }
      } else {
        resetSkipCountdown()
        isAnimating = false
      }
    }
  }
}
