# TimeMate

<p align="center">
  <img src="https://raw.githubusercontent.com/homielab/timemate/main/docs/assets/icon.png" alt="TimeMate Icon" width="100" height="100" style="border-radius: 22%; border: 0.5px solid rgba(0,0,0,0.1);" />
</p>

<p align="center">
  <b>A lightweight, menu bar Pomodoro timer for macOS</b>
</p>

<p align="center">
  <a href="https://homielab.com/en/page/timemate">Official Website</a> •
  <a href="https://github.com/homielab/timemate/issues">Report Issue</a> •
  <a href="https://ko-fi.com/homielab">Support Project</a>
</p>

---

## Overview

TimeMate is a clean, focused macOS application built around the Pomodoro Technique. Operating entirely from your menu bar, TimeMate helps you maintain deep focus and manage work-rest cycles without cluttering your desktop or Dock.

By alternating focused work sprints (e.g., 25 minutes) with short breaks (5 minutes) and scheduled long breaks, TimeMate promotes sustained concentration while preventing mental fatigue.

## Key Features

- **Menu Bar Integration**: Access your timer instantly from the macOS menu bar with zero desktop clutter. Right-click (or Control-click) the menu bar item for a quick menu: Start/Pause, Skip, Reset, Settings… and Quit. VoiceOver reads the item with the session and the time remaining, e.g. "TimeMate, Focus, 12 minutes, 34 seconds remaining".
- **Automated Workflow**: Seamlessly cycles between Focus, Short Break, and Long Break sessions. A long break comes after every 2–8 focus sessions (default 4); "Auto-start next session" and "Auto-start on launch" keep the timer going without clicks.
- **Custom Session Durations**: Set any focus or break length from 1 to 180 minutes (e.g. 50/10 or 90-minute deep work) by typing it or with the stepper.
- **Automatic Transitions**: Automatically switches to breaks to keep you in the flow state.
- **Subtle Notifications**: Receive gentle alerts when sessions complete without disruptive alarms. The banner shows even while TimeMate is in front, plays only your chosen alarm sound, and has **Start Next** / **Skip** buttons. It is time-sensitive, so it still shows while a Focus mode or Do Not Disturb is on; turn off "Break through Focus" in Settings → Alerts & Sound to let Focus hide it.
- **VoiceOver**: The duration and cycle steppers are named ("Focus minutes", "Cycles"…), the cycle dots read as "2 of 4 focus sessions done" and the progress ring says how much of the session is left.
- **Full-Screen Break Overlay**: Optional immersive break screen that encourages taking genuine rest. The animation runs only on the screen you work on, stays still when Reduce Motion is on, and VoiceOver announces the break and reads its countdown. Need more rest? **+5 min** lengthens the break; not a good moment? **Postpone** it by 1, 3 or 5 minutes and it comes back on its own. The Skip button appears after a delay you set in Settings → Alerts & Sound (0–30 s, default 5 s).
- **Statistics**: See how many pomodoros and focus minutes you completed today. Settings → Statistics shows the last 7 days (pomodoros and focus minutes per day, read day by day by VoiceOver), the week's total and the change against the 7 days before; **Export CSV…** saves every kept day as `date,pomodoros,minutes`. Completed sessions are kept for 90 days in a local JSON file (`~/Library/Containers/<bundle id>/Data/Library/Application Support/<bundle id>/session-history.json`) and can be cleared from Settings → Statistics. If that file can't be read, it is kept as `session-history.corrupt-<date>.json` (the latest one only) instead of being overwritten.
- **Daily Goal**: Set how many pomodoros you want to finish each day (Settings → Statistics → Daily goal, 1–24, off by default). The popover then shows "Today: 3/8 pomodoros · 75 min" with a small progress bar, the last 7 days mark each day you met the goal and count them ("Goal reached on 4 of 7 days"), the CSV export adds a `goal_reached` column (1/0), and a notification tells you once a day when the session that reaches the goal ends (if notifications are on).
- **Global Keyboard Shortcuts**: Start/pause with ⌃⌥P and skip the current session with ⌃⌥S from any app. Record your own combination (it must include ⌃ or ⌘) or turn each shortcut off in Settings → Keyboard Shortcuts. No Accessibility permission needed.
- **Shortcuts & Siri**: Automate TimeMate with the Shortcuts app — **Start Timer**, **Pause Timer**, **Skip Session** and **Get Timer Status** (returns the minutes left and says which session is running, e.g. "Focus, running, 12 min left"). Use them to turn on a Focus mode when a session starts, or ask Siri "Start TimeMate".
- **Survives Quit & Updates**: Quit, update or restart your Mac and the session picks up where it was — a running timer keeps counting from when it should end, a paused one stays paused, and the pomodoro count is kept. A session that ended while TimeMate was closed still counts in your statistics.
- **Keep Mac Awake**: Prevents your Mac from going to sleep during active focus sessions.
- **Customizable Interface**: Control dock icon visibility, notification preferences, and overlay behavior.
- **Multilingual Support**: Available in both English and Vietnamese.
- **Native & Efficient**: Built specifically for macOS with minimal system resource usage. The countdown ticks every second only while you can see it; with the menu bar time hidden and the popover closed, TimeMate wakes just once when the session ends. Starting at login stays quiet (no popover, no stolen focus) unless you turn on "Show timer when started at login"; "Today" rolls over at midnight and setting the clock never changes a running session's length.

## Screenshots

<div class="not-prose" style="display: flex; gap: 1rem; margin-top: 1rem; flex-wrap: wrap;">
  <img src="https://raw.githubusercontent.com/homielab/timemate/main/docs/screenshots/light.png" alt="TimeMate Light Mode" style="max-width: 300px; border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);" />
  <img src="https://raw.githubusercontent.com/homielab/timemate/main/docs/screenshots/dark.png" alt="TimeMate Dark Mode" style="max-width: 300px; border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);" />
</div>

## Requirements & Building

### Requirements
- macOS 13.5 or later
- Xcode 26 or later to build from source (the app icon uses the Icon Composer `AppIcon.icon` format)
- Swift Package Manager fetches the one dependency, [Lottie](https://github.com/airbnb/lottie-spm) (break-screen animation), on first build

### Building from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/homielab/timemate.git
   ```
2. Open the Xcode project:
   ```bash
   open src/TimeMate.xcodeproj
   ```
3. Build and run the project (`Cmd + R`) in Xcode, or build from the command line:
   ```bash
   xcodebuild -project src/TimeMate.xcodeproj -scheme TimeMate -configuration Debug \
     -derivedDataPath build/DerivedData build
   ```

### Running the Tests

The Pomodoro state machine is covered by unit tests in the `TimeMateTests` target:

```bash
xcodebuild -project src/TimeMate.xcodeproj -scheme TimeMate -configuration Debug \
  -derivedDataPath build/DerivedData test
```

Or press `Cmd + U` in Xcode.

Debug builds sign with `src/TimeMate/TimeMateDebug.entitlements` (no extra capabilities), so they build with any development team. Release builds use `src/TimeMate/TimeMate.entitlements`, which adds the Time Sensitive Notifications entitlement: the App ID needs that capability enabled in the Apple Developer portal.

### Code Style

The code is formatted with [swift-format](https://github.com/swiftlang/swift-format) (settings in
`.swift-format`: 2-space indent, 100 columns). Check it with:

```bash
swift format lint -r src/TimeMate src/TimeMateTests
```

A few older files still have warnings, so the check doesn't fail the build yet.

### Continuous Integration

`.github/workflows/test.yml` runs on every pull request and push to `main` (GitHub's `macos-26`
runner with Xcode 26): the swift-format check above, then the build and the unit tests with the
same `xcodebuild` command as in [Running the Tests](#running-the-tests), signed ad hoc
(`CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`) because CI has no Apple Development
certificate. The tests include a check that `en.lproj` and `vi.lproj` have the same strings with the
same format specifiers (`%@`, `%d`, `%lld`…), so a new string must be added to both languages.
Texts with a count that needs singular and plural forms ("1 pomodoro" / "2 pomodoros") go in
`Localizable.stringsdict` of both languages instead of `Localizable.strings` (Vietnamese only
needs the `other` form); the same check covers them.

### Project Layout

Sources are in `src/TimeMate/`:

- `PomodoroTimer.swift` — the timer state machine; `TimerSnapshot.swift` — the session it saves in
  user defaults to restore after a relaunch; `SettingsKey.swift` — all user-defaults keys.
- `AppDelegate.swift` — menu bar item, popover, global shortcuts, break overlay.
  `LaunchBehavior.swift` decides whether the popover opens at launch (not at login);
  `TickMode.swift` decides whether the timer ticks every second or only at the session's end.
- `ContentView.swift` — the popover; its parts are in `Views/` (`TimerDisplayView`,
  `ControlButtonsView`).
- `Settings/` — one file per settings section (`DurationsSection`, `AlertsSection`, …), shared
  building blocks in `SettingsComponents.swift`, the list of sections in `SettingsView.swift`.
- `BreakOverlay*.swift` — the full-screen break screen; `BreakOverlayRules.swift` decides when it
  shows and what a double Esc does (unit-tested).
- `Intents.swift` — Shortcuts actions (App Intents) and Siri phrases; they drive the shared
  `PomodoroTimer.shared` through `TimerIntentActions` (unit-tested). Vietnamese phrases are in
  `vi.lproj/AppShortcuts.strings`.
- `PrivacyInfo.xcprivacy` — the App Store privacy manifest (no tracking or collected data;
  required-reason APIs: user defaults, system uptime). Declare any new required-reason API there.
- `Log.swift` — `os.Logger` categories (`app`, `history`); use them instead of `print`.

## Feedback & Contributions

Contributions, bug reports, and feature requests are welcome. Feel free to open an issue or submit a pull request on the [GitHub repository](https://github.com/homielab/timemate/issues).

## Support

If you find TimeMate helpful and would like to support its ongoing development, consider buying a coffee:

[<img height="36" style="border:0px;height:36px;" src="https://storage.ko-fi.com/cdn/kofi1.png?v=6" border="0" alt="Buy Me a Coffee at ko-fi.com" />](https://ko-fi.com/homielab)

