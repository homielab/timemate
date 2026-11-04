# Changelog

All notable changes to TimeMate are documented here. Format: [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

## [3.10] - 2026-11-02

### Fixed

- Opening TimeMate again brings back its menu bar icon if you dragged it out. It can't hide forever.
- Restarting to change the language or reset settings no longer records your session twice.
- The break screen comes back when your displays reconnect, and keeps its Skip delay after a restart.
- Statistics → By hour now spreads a paused session over the hours you really worked.

## [3.9] - 2026-10-31

### Added

- Start Focus in Shortcuts can take a number of minutes, so you can automate a 15-minute session without changing Settings.

### Fixed

- Keyboard shortcuts show the keys of your keyboard layout, and combinations macOS already uses are refused.
- Undo Last Session shows the date when the session wasn't today.
- A duration you type in Settings is saved when the popover closes.
- Add Time in Shortcuts now says "No session to extend" when nothing is running.
- Reset All Settings tells you your history and statistics are kept.

## [3.8] - 2026-10-31

### Changed

- Get Timer Status and Get Today's Progress in Shortcuts return more details, so a shortcut can react to the timer's state.

### Fixed

- The "daily goal reached" notification also arrives when your last session ended just before midnight.
- Skip on a session that hasn't started no longer starts the break by accident, and Restart asks before throwing away finished sessions.
- Statistics follow your Mac's region and 12 or 24-hour clock.
- Exported CSV files are safe to open in a spreadsheet, and labels like @Acme or +5 stay as you typed them.
- After the break screen or popover closes, the app you were using gets your keyboard back, so you can keep typing.
- Settings fit small screens and scroll instead of running off the bottom.
- The Skip button delay on the break screen now holds for every way out of a break.
- Changing the language or resetting settings no longer pauses a running session.
- The alarm waits with the break screen when it waits for a full-screen app or a call.
- Quitting mid-session pauses it instead of counting it as finished when you come back hours later.
- Reset now says how many minutes of focus it saved to your history.
- Weekends don't break the streak works with weekends that fall on other days too.
- Plugging in or unplugging a display during a break no longer blanks the break screen.
- A few small fixes in Settings, VoiceOver and keyboard shortcuts.

## [3.7] - 2026-10-30

### Added

- Wait during calls and video: the break screen holds off while you are on a call or sharing your screen.
- Undo Last Session in Settings → Statistics removes the session you recorded last.

### Fixed

- Add Time in Shortcuts tells you how many minutes it added.
- The notification at the end of a break no longer skips your next focus session.
- A label you type after pressing Start is saved with that session.
- The "daily goal reached" notification shows again when you raise your goal and reach it the same day.
- A timer left idle overnight shows a fresh focus session in the morning.
- A session paused in the evening and finished the next day counts for the day and hour you really worked.
- More Vietnamese texts are translated.

## [3.6] - 2026-10-30

### Added

- Statistics: a By hour chart, By label totals, Daily average, Best day, your best streak, and Export all as CSV.
- Weekends don't break the streak, for people with a daily goal.
- Auto-pause when I'm away, and Resume when I'm back.
- What are you working on? lets you label a session, with a menu of recent labels.
- Add 5 Minutes button and keyboard shortcut for a running session.
- Start Focus with Label and Add Time in Shortcuts.
- The break screen shows today's progress, and the menu bar tooltip shows the time left.
- Menu bar time can show minutes only or just the icon.
- Separate switches for auto-start breaks and auto-start focus.
- Space, ⌘, ⌘→ and ⌘R work in the popover, and Restart asks before you lose progress.
- Pause when the Mac sleeps or the screen locks, so lunch doesn't count as a pomodoro.
- Break screen: +5 min, Postpone, a Skip button delay, and Don't interrupt full-screen apps.
- Choose a silent alarm, and a different sound for the end of a break.
- Shortcuts actions to start, pause, skip, reset and check the timer, with Siri phrases in English and Vietnamese.
- Right-click the menu bar item for a quick menu.
- Sessions of 1 to 180 minutes.
- Keyboard shortcuts that work while another app is in front.
- Today's progress, a daily goal with a streak, and 7 and 30-day statistics you can export.
- Notifications that break through Focus mode, and better VoiceOver support everywhere.

### Changed

- Uses much less energy, during breaks and all day.
- The end-of-session notification says what comes next.
- TimeMate no longer pops open when it starts at login.

### Fixed

- Auto-pause no longer pauses you during a video call or while a video plays.
- Skipping a focus session after half of it counts the time you worked.
- +5 min never stretches a session past 180 minutes.
- A session paused overnight starts a fresh cycle.
- Statistics, CSV export and the daily goal notification are more accurate.
- Squashed many more small bugs that liked to sneak in.

## [3.5] - 2026-10-25

### Changed

- The long break can last up to 60 minutes.
- A new app icon.

## [3.4] - 2026-09-20

### Added

- Auto-start on launch, in Settings → Automation.
- Preview the alarm sound next to the volume slider, which now shows a percentage.
- Tooltips that explain the auto-start and Keep Mac awake options.

### Changed

- A tidier Settings panel with clear sections and macOS-style switches.

### Fixed

- A few texts that were not translated in English and Vietnamese.

## [3.3]

See [releases](https://apps.apple.com/us/app/timemate-pomodoro-timer/id6754137356) for earlier changes.
