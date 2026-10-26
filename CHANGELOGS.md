# CHANGELOGS

All notable changes to TimeMate will be documented in this file.

## Unreleased

### Added

- Settings → Alerts & Sound → **Don't interrupt full-screen apps** (on by default): when the
  app in front is full screen (a presentation, a video), the break screen no longer pulls
  you out of it. The notification still arrives, and the break screen appears once you leave
  full screen, as long as the break lasts. It can't detect screen sharing in a normal window.
- Settings → Alerts & Sound: choose **None** for a silent alarm, and a separate sound for
  the end of a break (it follows the alarm sound until you pick one). Both pickers and
  their preview buttons are named for VoiceOver.
- A **Reset** keyboard shortcut (⌃⌥R, off by default; turn it on or record your own in
  Settings → Keyboard Shortcuts) and a **Reset Timer** Shortcuts action ("Reset TimeMate").
  Key names such as Space now show in the app's language.

- Shortcuts actions: Start Timer, Pause Timer, Skip Session and Get Timer Status
  (returns the minutes left and names the session), e.g. to turn on a Focus mode when a
  session starts. Siri phrases such as "Start TimeMate" work too (English and Vietnamese).
- Right-click (or Control-click) the menu bar item for a quick menu: Start / Pause
  (Resume, Continue Work), Skip, Reset, Settings… and Quit. A left click still opens
  the popover.
- VoiceOver reads the menu bar item with the session and the time remaining, e.g.
  "TimeMate, Focus, 12 minutes, 34 seconds remaining", instead of an unnamed button.
- Break screen: **+5 min** makes the break longer (or adds five more minutes once
  it has ended), and **Postpone 1 / 3 / 5 min** hides the break screen and brings the
  break back at its full length when the time is up. The popover shows "Break
  postponed" meanwhile. Both read clearly with VoiceOver.
- Settings → Alerts & Sound → "Skip button delay": choose how long the break screen
  waits before offering Skip and Postpone (0–30 s, default 5 s).
- Any session length from 1 to 180 minutes (e.g. 50/10 or a 90-minute focus):
  type the minutes in Settings → Durations or use the stepper; invalid entries
  are shown in red and not saved.
- Global keyboard shortcuts that work while another app is in front: ⌃⌥P starts or
  pauses the timer (and continues past a waiting break screen), ⌃⌥S skips to the next
  session. Change or turn off each one in Settings → Keyboard Shortcuts; a shortcut
  already taken by another app is flagged there. No Accessibility permission needed.
- Settings → Statistics shows the last 7 days (pomodoros and focus minutes per day),
  the week's total and the change against the previous 7 days. **Export CSV…** saves
  the whole 90-day history as `date,pomodoros,minutes`, one row per day.
- Today's statistics: the popover shows "Today: N pomodoros · X min" for completed
  focus sessions. Completed sessions (skipped ones don't count) are saved for 90 days
  and survive restarts; Settings → Statistics → "Reset Statistics" clears them.
- Unit test suite (`TimeMateTests`, 19 tests) for the Pomodoro state machine: session
  progression and long-break cycles, auto-start, pause/resume, and the break screen's
  "continue" flow. The timer now takes its `UserDefaults` and clock through its
  initializer, and settings keys live in one shared `SettingsKey` enum.
- Settings → System → "Show timer when started at login" (off by default).
- Session-complete notifications are time-sensitive, so they still show during a Focus mode
  or Do Not Disturb; Settings → Alerts & Sound → "Break through Focus" (on by default).
- VoiceOver names the duration and cycle steppers, reads the cycle dots as "2 of 4 focus
  sessions done" and the progress ring as the percentage of the session left.
- Continuous integration on GitHub Actions: every pull request and push to `main` is
  built and tested on macOS with Xcode 26 and checked with swift-format. New tests
  cover when the break screen shows, the double-Esc shortcut on it, and that the
  English and Vietnamese strings have the same keys and format specifiers.
- Privacy manifest (`PrivacyInfo.xcprivacy`) as the App Store requires: no tracking, no
  data collected; declares user defaults (CA92.1, the app's own settings) and the system
  uptime used to time sessions (35F9.1). The Lottie package brings its own manifest.
- Daily goal: set how many pomodoros you want each day (Settings → Statistics, 1–24, off
  by default). The popover shows "Today: 3/8 pomodoros" with a progress bar, the last 7 days
  mark the days you met it, the CSV export gets a `goal_reached` column, and a notification
  tells you once a day when you reach it.

### Changed

- TimeMate no longer opens its popover and takes focus when it starts at login; it still
  opens on the first launch and when you open the app yourself. No Dock icon flashes at launch.
- Uses less energy: the countdown ticks every second only while you can see it (time in the
  menu bar, popover open, break screen), otherwise the app wakes once when the session ends.
- Build number is now 15, matching the 3.5 release commit.
- README: correct requirements (macOS 13.5, Xcode 26), command-line build and test commands.
- Internal: the popover and settings code is split into `Views/` and one file per
  settings section under `Settings/`; no visible change.
- Break screen: the cat animation plays only on the screen you work on (less CPU with
  several displays), and that screen gets the keyboard focus. With Reduce Motion on,
  the break screen shows a still image and appears without fading.
- VoiceOver announces "Break started, 5 minutes" and reads the break countdown and
  the Skip / Continue buttons with their Esc shortcut.

### Fixed

- The break screen's clock stops when the screen is hidden, and the Esc and screen-change
  listeners are removed when they are not needed.
- When a break has ended and waits on the break screen, the popover's main button now
  reads "Continue Work" and starts the next focus session instead of running the break
  again.
- Changing a session length in Settings → Durations updates the idle timer right away
  instead of on the next Start. Clicking a TimeMate notification opens the popover.
- English statistics use singular and plural forms: "Today: 1 pomodoro" instead of
  "1 pomodoros" (also the week total, the change against the previous week and VoiceOver's
  "1 minute"). Vietnamese is unchanged.
- An unreadable statistics file no longer gets overwritten and lose its sessions: it is
  kept as `session-history.corrupt-<date>.json` next to it (the latest one only) and
  statistics start over.
- A broken "Cycles" value in the preferences (below 1 or above 8) no longer crashes the
  popover; it is treated as 1–8.
- "Today" in the popover and the Statistics week roll over at midnight and after a change of
  the system time or time zone; setting the clock no longer cuts short or stretches a running
  session.
- Quitting, updating or a crash no longer loses the session: a running timer keeps
  counting down after relaunch, a paused one stays paused, and the pomodoro count is
  kept. A session that ended while TimeMate was closed is added to the statistics on
  the day it ended and the next session follows (started only if "Auto-start next
  session" is on), without a late alarm or notification.
- "Review on App Store" now opens TimeMate's review page in the App Store, and
  the unused push-notification entitlement was removed.
- The "session complete" notification now shows as a banner even when TimeMate is
  in front (e.g. as the break screen opens), has "Start Next" and "Skip" buttons,
  and no longer plays a second sound on top of the alarm chosen in Settings.
- The break screen no longer disappears when it is shown again right after being
  hidden (it used to close at the end of the fade-out).
- Changing the language or resetting all settings relaunches the app through Launch
  Services instead of a shell command, so it works inside the App Sandbox.
- Less CPU while the timer runs: the closed popover no longer redraws every
  second, and the menu bar item updates in place when "Hide time" is toggled.
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

## 3.5

### Changed

- The long break can now last up to 60 minutes (it was 30).
- Updated app icon (Icon Composer format).

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

## 3.3 – Previous release

See [releases](https://apps.apple.com/us/app/timemate-pomodoro-timer/id6754137356) for earlier changes.
