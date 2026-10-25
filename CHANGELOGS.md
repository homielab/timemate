# CHANGELOGS

All notable changes to TimeMate will be documented in this file.

## Unreleased

### Added

- Today's statistics: the popover shows "Today: N pomodoros · X min" for completed
  focus sessions. Completed sessions (skipped ones don't count) are saved for 90 days
  and survive restarts; Settings → Statistics → "Reset Statistics" clears them.
- Unit test suite (`TimeMateTests`, 19 tests) for the Pomodoro state machine: session
  progression and long-break cycles, auto-start, pause/resume, and the break screen's
  "continue" flow. The timer now takes its `UserDefaults` and clock through its
  initializer, and settings keys live in one shared `SettingsKey` enum.

### Fixed

- Default settings are now registered before they are read, so the Dock icon is
  hidden on a fresh install as intended.
- "Keep Mac awake" now holds the Mac awake only while a focus session is running,
  not while idle, paused or on a break.
- When notification permission is denied, Settings → Alerts & Sound shows a notice
  with a button that opens System Settings.
- The countdown now follows the real clock: a session no longer runs longer
  than its set length when the Mac sleeps or macOS throttles the app (App Nap).
  After waking, the timer shows the true remaining time, and a session that
  ended during sleep finishes once with a single notification.
- "Start at Login" now actually registers the app as a login item
  (`SMAppService.mainApp`) and no longer re-registers it every time the
  settings panel opens.
- When macOS needs approval for the login item, a hint with an
  "Open System Settings" button appears next to the toggle.
- "Keep window on top" now works: when on, the popover stays open when you click
  elsewhere and closes from the menu bar icon or the Escape key; when off, it
  closes on outside clicks as before.

## 3.4

### Added

- **Auto-start on launch** option: automatically starts the focus timer when the
  app opens (including launches via "Start at Login"). Disabled by default.
  (Settings → Automation)
- **Alarm sound preview** button next to the volume slider, playing the selected
  alarm at the current volume. (Settings → Alerts & Sound)
- Volume slider now shows a **percentage readout**.
- Tooltips explaining "Auto-start next session", "Auto-start on launch" and
  "Keep Mac awake".

### Changed

- **Settings panel reorganized** into titled, card-based sections:
  Durations, Automation, Alerts & Sound, Appearance, System, Language, and
  About & Support.
- Toggles now use macOS System Settings–style switches, aligned to the right
  edge across all rows.
- Duration values are right-aligned in a fixed column with monospaced digits so
  steppers line up.
- Related settings were regrouped logically (e.g., "Keep window on top" moved to
  Appearance; notifications, break overlay and sound live together).

### Fixed

- "Hide time in menu bar" was displayed untranslated in all languages; it is now
  localized in English and Vietnamese.
- "Clear Background Color" (accessibility label) is now localized in English and
  Vietnamese.

## [3.3] – Previous release

See [releases](https://apps.apple.com/us/app/timemate-pomodoro-timer/id6754137356) for earlier changes.
