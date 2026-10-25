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
- **Automated Workflow**: Seamlessly cycles between Focus, Short Break, and Long Break sessions.
- **Custom Session Durations**: Set any focus or break length from 1 to 180 minutes (e.g. 50/10 or 90-minute deep work) by typing it or with the stepper.
- **Automatic Transitions**: Automatically switches to breaks to keep you in the flow state.
- **Subtle Notifications**: Receive gentle alerts when sessions complete without disruptive alarms. The banner shows even while TimeMate is in front, plays only your chosen alarm sound, and has **Start Next** / **Skip** buttons.
- **Full-Screen Break Overlay**: Optional immersive break screen that encourages taking genuine rest. The animation runs only on the screen you work on, stays still when Reduce Motion is on, and VoiceOver announces the break and reads its countdown. Need more rest? **+5 min** lengthens the break; not a good moment? **Postpone** it by 1, 3 or 5 minutes and it comes back on its own. The Skip button appears after a delay you set in Settings → Alerts & Sound (0–30 s, default 5 s).
- **Today's Statistics**: See how many pomodoros and focus minutes you completed today. Completed sessions are kept for 90 days in a local JSON file (`~/Library/Containers/<bundle id>/Data/Library/Application Support/<bundle id>/session-history.json`) and can be cleared from Settings → Statistics.
- **Global Keyboard Shortcuts**: Start/pause with ⌃⌥P and skip the current session with ⌃⌥S from any app. Record your own combination (it must include ⌃ or ⌘) or turn each shortcut off in Settings → Keyboard Shortcuts. No Accessibility permission needed.
- **Shortcuts & Siri**: Automate TimeMate with the Shortcuts app — **Start Timer**, **Pause Timer**, **Skip Session** and **Get Timer Status** (returns the minutes left and says which session is running, e.g. "Focus, running, 12 min left"). Use them to turn on a Focus mode when a session starts, or ask Siri "Start TimeMate".
- **Keep Mac Awake**: Prevents your Mac from going to sleep during active focus sessions.
- **Customizable Interface**: Control dock icon visibility, notification preferences, and overlay behavior.
- **Multilingual Support**: Available in both English and Vietnamese.
- **Native & Efficient**: Built specifically for macOS with minimal system resource usage.

## Screenshots

<div class="not-prose" style="display: flex; gap: 1rem; margin-top: 1rem; flex-wrap: wrap;">
  <img src="https://raw.githubusercontent.com/homielab/timemate/main/docs/screenshots/light.png" alt="TimeMate Light Mode" style="max-width: 300px; border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);" />
  <img src="https://raw.githubusercontent.com/homielab/timemate/main/docs/screenshots/dark.png" alt="TimeMate Dark Mode" style="max-width: 300px; border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);" />
</div>

## Requirements & Building

### Requirements
- macOS 13.0 or later
- Xcode 14.0 or later (for building from source)

### Building from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/homielab/timemate.git
   ```
2. Open the Xcode project:
   ```bash
   open src/TimeMate.xcodeproj
   ```
3. Build and run the project (`Cmd + R`) in Xcode.

### Running the Tests

The Pomodoro state machine is covered by unit tests in the `TimeMateTests` target:

```bash
xcodebuild test -project src/TimeMate.xcodeproj -scheme TimeMate -derivedDataPath build/DerivedData
```

Or press `Cmd + U` in Xcode.

### Project Layout

Sources are in `src/TimeMate/`:

- `PomodoroTimer.swift` — the timer state machine; `SettingsKey.swift` — all user-defaults keys.
- `AppDelegate.swift` — menu bar item, popover, global shortcuts, break overlay.
- `ContentView.swift` — the popover; its parts are in `Views/` (`TimerDisplayView`,
  `ControlButtonsView`).
- `Settings/` — one file per settings section (`DurationsSection`, `AlertsSection`, …), shared
  building blocks in `SettingsComponents.swift`, the list of sections in `SettingsView.swift`.
- `BreakOverlay*.swift` — the full-screen break screen.
- `Intents.swift` — Shortcuts actions (App Intents) and Siri phrases; they drive the shared
  `PomodoroTimer.shared` through `TimerIntentActions` (unit-tested). Vietnamese phrases are in
  `vi.lproj/AppShortcuts.strings`.

## Feedback & Contributions

Contributions, bug reports, and feature requests are welcome. Feel free to open an issue or submit a pull request on the [GitHub repository](https://github.com/homielab/timemate/issues).

## Support

If you find TimeMate helpful and would like to support its ongoing development, consider buying a coffee:

[<img height="36" style="border:0px;height:36px;" src="https://storage.ko-fi.com/cdn/kofi1.png?v=6" border="0" alt="Buy Me a Coffee at ko-fi.com" />](https://ko-fi.com/homielab)

