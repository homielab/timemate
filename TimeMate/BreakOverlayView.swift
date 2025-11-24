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
  @State private var currentTime = Date()
  @State private var showSkipButton = false
  @State private var countdown = 5
  @State private var isAnimating = false
  @State private var currentTip = ""
  
  let timerPublisher = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
          .animation(.easeOut(duration: 1.0), value: isAnimating)

        Spacer()

        // Center: Image, Relaxation Tip & Timer
        VStack(spacing: 30) {
          LottieView(animation: .named("cat-playing"))
            .playing(loopMode: .loop)
            .frame(width: 535, height: 228)
            .opacity(isAnimating ? 1 : 0)
            .scaleEffect(isAnimating ? 1 : 0.9)
            .animation(.easeOut(duration: 1.5), value: isAnimating)

          VStack(spacing: 10) {
            Text(LocalizedStringKey(currentTip))
              .font(.system(size: 32, weight: .light))
              .multilineTextAlignment(.center)
              .foregroundColor(.white.opacity(0.9))
              .padding(.horizontal, 40)
              .opacity(isAnimating ? 1 : 0)
              .offset(y: isAnimating ? 0 : 20)
              .animation(.easeOut(duration: 1.0).delay(0.3), value: isAnimating)
          }

          Text(timer.timeRemaining.toMinuteSecondString())
            .font(.system(size: 120, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.top, 20)
            .opacity(isAnimating ? 1 : 0)
            .animation(.easeOut(duration: 1.0).delay(0.9), value: isAnimating)
        }

        Spacer()

        // Bottom: Skip Button & Hint
        VStack(spacing: 16) {
          if showSkipButton {
            Button(action: {
              timer.skipSession()
            }) {
              Text(LocalizedStringKey("Skip Break"))
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(
                  Capsule()
                    .fill(Color.white.opacity(0.1))
                )
                .overlay(
                  Capsule()
                    .strokeBorder(Color.white, lineWidth: 2)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .transition(.opacity)
          } else {
            Text(String(format: NSLocalizedString("Skip available in %d", comment: ""), countdown))
              .font(.body)
              .foregroundColor(.white.opacity(0.5))
              .padding(.vertical, 12)
          }

          Text(LocalizedStringKey("Press Esc twice to skip"))
            .font(.caption)
            .foregroundColor(.white.opacity(0.4))
            .padding(.top, 8)
        }
        .padding(.bottom, 60)
        .frame(height: 120)
        .opacity(isAnimating ? 1 : 0)
        .animation(.easeOut(duration: 1.0).delay(1.2), value: isAnimating)
      }
    }
    .onAppear {
      isAnimating = true
      currentTip = RelaxationTips.random()
    }
    .onReceive(timerPublisher) { input in
      currentTime = input

      if timer.state == .active
        && (timer.currentSessionType == .shortBreak || timer.currentSessionType == .longBreak)
      {
        if !isAnimating {
          isAnimating = true
          currentTip = RelaxationTips.random()
        }
        if countdown > 0 {
          countdown -= 1
        } else {
          withAnimation {
            showSkipButton = true
          }
        }
      } else {
        countdown = 5
        showSkipButton = false
        isAnimating = false
      }
    }
  }
}
