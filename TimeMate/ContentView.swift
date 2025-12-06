//  Created by homielab.com

import ServiceManagement
import StoreKit
import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
  @EnvironmentObject var timer: PomodoroTimer
  @EnvironmentObject var appDelegate: AppDelegate
  @State private var settingsVisible = false

  @AppStorage("backgroundColorHex") private var backgroundColorHex: String = ""
  @AppStorage("showProgressCircle") private var showProgressCircle = true
  @AppStorage("backgroundImagePath") private var backgroundImagePath: String = ""
  @AppStorage("focusDuration") private var focusDuration = 25
  @AppStorage("shortBreakDuration") private var shortBreakDuration = 5
  @AppStorage("longBreakDuration") private var longBreakDuration = 15

  var body: some View {
    VStack(spacing: 12) {
      TimerDisplayView(settingsVisible: $settingsVisible, showProgressCircle: $showProgressCircle)
      ControlButtonsView()

      if settingsVisible {
        Divider()
        ScrollView {
          SettingsView(
            showProgressCircle: $showProgressCircle, backgroundColorHex: $backgroundColorHex
          )
          .padding(.trailing, 8)
        }
        .frame(maxHeight: 450)
      }
    }
    .padding()
    .frame(minWidth: 280)
    .background(Color(hex: backgroundColorHex) ?? .clear)
    .contentShape(Rectangle())
    .onChange(of: [focusDuration, shortBreakDuration, longBreakDuration]) { _ in
      if timer.state == .idle {
        timer.stopTimer()
      }
    }
    .onChange(of: [settingsVisible, showProgressCircle]) { _ in
      appDelegate.updatePopoverSize()
    }
  }
}

// MARK: - Reusable Sub-views

private struct TimerDisplayView: View {
  @EnvironmentObject var timer: PomodoroTimer
  @Binding var settingsVisible: Bool
  @Binding var showProgressCircle: Bool

  @AppStorage("longBreakInterval") private var longBreakInterval = 4

  private var accentColor: Color {
    switch timer.currentSessionType {
    case .focus: return .accentColor
    case .shortBreak: return .green
    case .longBreak: return .teal
    }
  }

  private var sessionIcon: String {
    switch timer.currentSessionType {
    case .focus: return "brain.head.profile"
    case .shortBreak: return "cup.and.saucer.fill"
    case .longBreak: return "chair.lounge.fill"
    }
  }

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        HStack(spacing: 6) {
          Image(systemName: sessionIcon)
          Text(LocalizedStringKey(timer.currentSessionType.rawValue))
        }
        .font(.headline)
        .foregroundColor(.secondary)

        Spacer()

        SettingsButton(settingsVisible: $settingsVisible)
      }

      if showProgressCircle {
        ZStack {
          Circle()
            .stroke(lineWidth: 12)
            .foregroundColor(Color(nsColor: .separatorColor))

          Circle()
            .stroke(lineWidth: 10)
            .foregroundColor(.gray.opacity(0.15))

          Circle().trim(from: 0.0, to: CGFloat(timer.progress))
            .stroke(style: .init(lineWidth: 10, lineCap: .round, lineJoin: .round))
            .foregroundColor(accentColor)
            .rotationEffect(Angle(degrees: 270.0))
            .animation(.linear, value: timer.progress)

          VStack {
            Text(timer.timeRemaining.toMinuteSecondString())
              .font(.system(size: 32, weight: .bold, design: .monospaced))
              .foregroundColor(accentColor)
          }
        }
        .frame(width: 120, height: 120)
      } else {
        Text(timer.timeRemaining.toMinuteSecondString())
          .font(.system(size: 32, weight: .bold, design: .monospaced))
          .foregroundColor(accentColor)
      }

      CycleIndicatorView(
        completed: timer.focusSessionsCompleted,
        total: longBreakInterval,
        isLongBreak: timer.currentSessionType == .longBreak
      )
    }
  }
}

private struct SettingsButton: View {
  @Binding var settingsVisible: Bool

  var body: some View {
    Button {
      settingsVisible.toggle()
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "gearshape.fill")
        Image(systemName: settingsVisible ? "chevron.up" : "chevron.down")
          .font(.system(size: 10, weight: .bold))
          .rotationEffect(.degrees(settingsVisible ? 0 : 0))
          .animation(.easeInOut(duration: 0.3), value: settingsVisible)
      }
      .padding(5)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundColor(.secondary)
    .background(Color.secondary.opacity(0.1))
    .cornerRadius(5)
  }
}

private struct CycleIndicatorView: View {
  let completed: Int
  let total: Int
  let isLongBreak: Bool

  var body: some View {
    ZStack {
      HStack(spacing: 6) {
        ForEach(1...total, id: \.self) { cycle in
          if cycle <= completed {
            Image(systemName: "checkmark.circle.fill")
          } else {
            Image(systemName: "circle")
          }
        }
      }
      .font(.system(size: 12))
      .foregroundColor(.secondary)
      .opacity(isLongBreak ? 0.0 : 1.0)

      Image(systemName: "cup.and.saucer.fill")
        .font(.callout)
        .foregroundColor(.secondary)
        .opacity(isLongBreak ? 1.0 : 0.0)
    }
    .frame(height: 20, alignment: .center)
    .animation(.easeInOut(duration: 0.2), value: isLongBreak)
  }
}

private struct ControlButtonsView: View {
  @EnvironmentObject var timer: PomodoroTimer

  private var mainButtonIconName: String {
    switch timer.state {
    case .active: return "pause.fill"
    case .paused, .idle: return "play.fill"
    }
  }

  private var mainButtonColor: Color {
    switch timer.state {
    case .active: return .orange
    case .paused, .idle: return .green
    }
  }

  private var mainButtonAccessibilityLabel: LocalizedStringKey {
    switch timer.state {
    case .active: return "Pause"
    case .paused: return "Resume"
    case .idle: return "Start"
    }
  }

  private var mainButtonAction: () -> Void {
    switch timer.state {
    case .active: return timer.pauseTimer
    case .paused, .idle: return timer.startTimer
    }
  }

  var body: some View {
    HStack(spacing: 16) {
      Button {
        timer.restartCycle()
      } label: {
        Image(systemName: "backward.end.fill")
      }
      .buttonStyle(.bordered).controlSize(.large).accessibilityLabel("Restart")

      Button {
        timer.stopTimer()
      } label: {
        Image(systemName: "arrow.counterclockwise")
      }
      .buttonStyle(.bordered).controlSize(.large).disabled(timer.state == .idle).accessibilityLabel(
        "Reset")

      Button(action: mainButtonAction) { Image(systemName: mainButtonIconName).font(.title) }
        .buttonStyle(.borderedProminent).tint(mainButtonColor).controlSize(.large)
        .accessibilityLabel(mainButtonAccessibilityLabel)

      Button {
        timer.skipSession()
      } label: {
        Image(systemName: "forward.end.fill")
      }
      .buttonStyle(.bordered).controlSize(.large).accessibilityLabel("Skip")
    }
  }
}

private struct SettingsView: View {
  @Binding var showProgressCircle: Bool
  @Binding var backgroundColorHex: String

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      DurationSettingsView()
      Divider()
      SystemSettingsView(
        showProgressCircle: $showProgressCircle, backgroundColorHex: $backgroundColorHex)
      Divider()
      LanguageSettingsView()
      Divider()
      AboutAndSupportView()
    }
  }
}

private struct SystemSettingsView: View {
  @EnvironmentObject var appDelegate: AppDelegate
  @Binding var showProgressCircle: Bool
  @Binding var backgroundColorHex: String

  @AppStorage("hideDockIcon") private var hideDockIcon = true
  @AppStorage("alwaysVisible") private var alwaysVisible = false
  @AppStorage("startAtLogin") private var startAtLogin = false

  @AppStorage("autoStartNextSession") private var autoStartNextSession = true
  @AppStorage("alarmSound") private var alarmSound = "Glass"
  @AppStorage("alarmVolume") private var alarmVolume: Double = 1.0
  @AppStorage("keepAwake") private var keepAwake = false
  @AppStorage("overlayEnabled") private var overlayEnabled = true
  @AppStorage("notificationsEnabled") private var notificationsEnabled = true
  @AppStorage("hideMenuBarTime") private var hideMenuBarTime = false

  private let soundOptions = [
    "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr",
    "Sosumi", "Submarine", "Tink",
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle("Start at Login", isOn: $startAtLogin)
        .onAppear {
          let service = SMAppService()
          startAtLogin = (service.status == .enabled)
        }
        .onChange(of: startAtLogin) { newValue in
          do {
            let service = SMAppService()
            if newValue {
              try service.register()
            } else {
              try service.unregister()
            }
          } catch {
            print("Failed to update Start at Login setting: \(error)")
            startAtLogin.toggle()
          }
        }

      Toggle("Hide Dock icon", isOn: $hideDockIcon)
        .onChange(of: hideDockIcon) { newValue in
          appDelegate.setDockIcon(hidden: newValue)
        }
      Toggle("Keep window on top", isOn: $alwaysVisible)
        .onChange(of: alwaysVisible) { newValue in
          appDelegate.setPopoverBehavior(alwaysVisible: newValue)
        }
      Toggle("Keep Mac awake", isOn: $keepAwake)
        .onChange(of: keepAwake) { newValue in
          appDelegate.setKeepAwake(enabled: newValue)
        }
      Divider()
      Toggle(LocalizedStringKey("Enable Break Overlay"), isOn: $overlayEnabled)
      Toggle(LocalizedStringKey("Enable Notifications"), isOn: $notificationsEnabled)
      Divider()
      Toggle("Hide time in menu bar", isOn: $hideMenuBarTime)
        .onChange(of: hideMenuBarTime) { newValue in
          appDelegate.updateMenuBarWidth(hideTime: newValue)
        }
      Toggle("Show Progress Circle", isOn: $showProgressCircle)
      Toggle("Auto-start next session", isOn: $autoStartNextSession)
      Picker("Alarm Sound", selection: $alarmSound) {
        ForEach(soundOptions, id: \.self) { Text($0) }
      }
      HStack {
        Text("Volume")
        Slider(value: $alarmVolume, in: 0.0...1.0)
      }
      HStack(alignment: .center, spacing: 8) {
        Text("Background Color")
        CustomColorPicker(hexColor: $backgroundColorHex)
          .fixedSize()

        Button {
          backgroundColorHex = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .accessibilityLabel(Text("Clear Background Color"))
      }
    }
  }
}

private struct CustomColorPicker: NSViewRepresentable {
  @Binding var hexColor: String

  func makeNSView(context: Context) -> NSColorWell {
    let colorWell = NSColorWell(style: .minimal)
    if #available(macOS 14.0, *) {
      colorWell.supportsAlpha = true
    }
    colorWell.action = #selector(context.coordinator.colorChanged(_:))
    colorWell.target = context.coordinator
    colorWell.color = NSColor(Color(hex: hexColor) ?? .clear)
    return colorWell
  }

  func updateNSView(_ nsView: NSColorWell, context: Context) {
    nsView.color = NSColor(Color(hex: hexColor) ?? .clear)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  class Coordinator: NSObject {
    var parent: CustomColorPicker

    init(_ parent: CustomColorPicker) {
      self.parent = parent
    }

    @objc func colorChanged(_ sender: NSColorWell) {
      parent.hexColor = Color(sender.color).toHex() ?? ""
    }
  }
}

private struct AppActionsView: View {
  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Spacer()
        Button {
          NSApplication.shared.terminate(nil)
        } label: {
          Image(systemName: "power")
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
      }
    }
  }
}

// MARK: - Settings Sub-components

private struct DurationSettingsView: View {
  @AppStorage("focusDuration") private var focusDuration = 25
  @AppStorage("shortBreakDuration") private var shortBreakDuration = 5
  @AppStorage("longBreakDuration") private var longBreakDuration = 15
  @AppStorage("longBreakInterval") private var longBreakInterval = 4

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 8) {
      GridRow(alignment: .center) {
        Text("Focus")
        Spacer(minLength: 16)
        Text(String(format: NSLocalizedString("minutes_format", comment: ""), focusDuration))
        Stepper("", value: $focusDuration, in: 5...60, step: 5).labelsHidden()
      }
      GridRow(alignment: .center) {
        Text("Short Break")
        Spacer(minLength: 16)
        Text(String(format: NSLocalizedString("minutes_format", comment: ""), shortBreakDuration))
        Stepper("", value: $shortBreakDuration, in: 1...15, step: 1).labelsHidden()
      }
      GridRow(alignment: .center) {
        Text("Long Break")
        Spacer(minLength: 16)
        Text(String(format: NSLocalizedString("minutes_format", comment: ""), longBreakDuration))
        Stepper("", value: $longBreakDuration, in: 10...30, step: 5).labelsHidden()
      }
      GridRow(alignment: .center) {
        Text("Cycles")
        Spacer(minLength: 16)
        Text("\(longBreakInterval)")
        Stepper("", value: $longBreakInterval, in: 2...8).labelsHidden()
      }
    }
    .frame(maxWidth: .infinity)
  }
}

private struct LanguageSettingsView: View {
  @State private var selectedLanguage: String = "system"

  private var savedLanguageCode: String {
    guard let languages = UserDefaults.standard.stringArray(forKey: "AppleLanguages"),
      let lang = languages.first
    else { return "system" }
    if lang.hasPrefix("en") { return "en" }
    if lang.hasPrefix("vi") { return "vi" }
    return "system"
  }

  var body: some View {
    Picker("Language", selection: $selectedLanguage) {
      Text("System Default").tag("system")
      Text("English").tag("en")
      Text("Vietnamese").tag("vi")
    }
    .onAppear { self.selectedLanguage = savedLanguageCode }
    .onChange(of: selectedLanguage) { newValue in
      guard newValue != savedLanguageCode else { return }
      if newValue == "system" {
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
      } else {
        UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
      }
      restartApp()
    }
  }
}

private struct AboutAndSupportView: View {

  @State private var showingResetAlert = false

  var body: some View {
    VStack(alignment: .leading) {
      MenuItemButton(title: "About", systemImage: "info.circle") {
        if let url = URL(string: "https://homielab.com/page/timemate") {
          NSWorkspace.shared.open(url)
        }
      }

      MenuItemButton(title: "Support", systemImage: "envelope.fill") {
        if let url = URL(string: "mailto:contact@homielab.com") {
          NSWorkspace.shared.open(url)
        }
      }

      MenuItemButton(title: "Review on App Store", systemImage: "star.fill") {
        SKStoreReviewController.requestReview()
      }

      #if DEBUG
        MenuItemButton(title: "Donate", systemImage: "heart.fill") {
          if let url = URL(string: "https://ko-fi.com/homielab") { NSWorkspace.shared.open(url) }
        }
      #endif

      MenuItemButton(title: "Reset All Settings", systemImage: "arrow.counterclockwise.circle") {
        showingResetAlert = true
      }

      MenuItemButton(title: "Quit", systemImage: "power") {
        NSApplication.shared.terminate(nil)
      }

      Divider().padding(.vertical, 4)

      Text(
        String(
          format: NSLocalizedString("Version %@", comment: ""),
          "\(Bundle.main.appVersion) (\(Bundle.main.appBuild))")
      )
      .font(.caption).foregroundColor(.secondary)
      .padding(.horizontal, 10)
    }
    .alert("Reset Settings?", isPresented: $showingResetAlert) {
      Button("Reset", role: .destructive) {
        resetAllSettings()
      }
      Button("Cancel", role: .cancel) {
      }
    } message: {
      Text(
        "This will restore all settings to their default values and restart the app. Are you sure?")
    }
  }
}

// MARK: - Helper Views

private struct MenuItemButton: View {
  let title: LocalizedStringKey
  let systemImage: String?
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack {
        if let systemImage = systemImage {
          Image(systemName: systemImage)
            .font(.system(size: 14))
            .frame(width: 20)
        }
        Text(title)
        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .background(isHovering ? Color.secondary.opacity(0.2) : Color.clear)
      .cornerRadius(5)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovering = hovering
    }
  }
}
