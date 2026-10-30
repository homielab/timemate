# CHANGELOGS

All notable changes to TimeMate will be documented in this file.

## Unreleased

### Fixed

- A duration typed in Settings is saved when the popover closes; Esc while typing puts back the old value, a second Esc closes the popover.
- The Add Time shortcut with no session running now says "No session to extend" (banner and VoiceOver), and a label typed after Start shows in the backup "session complete" notification.
- Reset All Settings says your history and statistics are kept and language, shortcuts and Start at Login go back to defaults; if TimeMate can't reopen itself it asks you to open it again.

## 3.8

### Changed

- The Shortcuts actions **Get Timer Status** and **Get Today's Progress** now return an object with fields instead of a single number, so a shortcut can branch on them: the timer's State (Not Started, Running, Paused), Session (Focus, Short Break, Long Break), Minutes Left, Seconds Left, Label and place in the cycle; today's Pomodoros, Focus Minutes, Daily goal, Goal Reached and Streak Days. Used as before, the result still reads as the minutes left or the pomodoros done.

### Fixed

- The "daily goal reached" notification now also comes when the goal's last session ended just before midnight and the Mac or app caught up shortly after it. With auto-start on, the "session complete" banner is no longer replaced by the next session's backup notification.
- Skip on a session that hasn't started (⌘→, ⌃⌥S, the menu bar menu) now only moves to the next session: it no longer starts the break and its full-screen break screen. Restart (⏮) now also asks before throwing away focus sessions already done in the cycle, or a break screen waiting to continue.
- Statistics follow your Mac's region and 12/24-hour setting in the app's language: "By hour", Undo Last Session, numbers and dates now match (for example "09:00 – 10:00" on a 24-hour clock), and VoiceOver skips hours without focus.
- The "Could not turn on Start at Login" message goes away once Start at Login is on (for example after turning it on in System Settings), and the Export CSV save panel no longer slips behind another app when opened from the popover.
- A session label such as `+ 1+1` (a space after the sign) is now exported to CSV with a leading `'` so spreadsheets don't run it as a formula.
- When the break screen or the popover closes, the app you were working in gets the keyboard back, so you can keep typing without clicking it first.
- The popover's settings fit small screens (such as a 13-inch 1440×900 display): the list scrolls instead of running off the bottom.
- The break screen's **Skip button delay** now also holds Reset: the Reset shortcut, the menu bar menu and the Shortcuts action **Reset Timer** no longer end the break before the delay runs out.
- Changing the language or **Reset All Settings** restarts TimeMate without pausing a running session.
- When the break screen waits for a full-screen app or a call (**Don't interrupt full-screen apps**, **Wait during calls and video**), the alarm sound waits too and plays once when the break screen shows; a break skipped or reset before then stays silent. The notification still arrives at once.
- Resetting with the keyboard shortcut or the Shortcuts action **Reset Timer** now says "Recorded N min of focus" when the focus time so far was saved to your history.
- VoiceOver now reads which session the "What are you working on?" label applies to, not only the tooltip.
- The break screen's **Skip button delay** now holds for every way out: until it runs out, the Skip and Start/Pause shortcuts, the menu bar menu, the notification's Skip button and the Shortcuts actions Skip Session and Pause Timer beep or report "Skip available in N s" instead of ending or pausing the break.
- Quitting TimeMate mid-session (Quit, an update, logging out or shutting down) now pauses the session with the time it had left instead of counting it as finished when you open the app hours later, so your history, streak and daily goal only hold time you worked. A crash or force quit still counts the session as before.
- A session length over 180 minutes or a cycle count of 1, left by an older version or set with `defaults write`, is brought back into Settings' range (1–180 minutes, 2–8 cycles), so Settings shows exactly what the timer runs.
- Settings → Statistics → **By label**: the "Other" bar no longer runs over the minutes and out of the card when the labels outside the top five add up to more than the longest one.
- **Export sessions CSV…** keeps labels such as `@Acme`, `-research` or `+5` as typed; only labels a spreadsheet would run as a formula (`=SUM(1)`, `-1+1`, `@A1`) still get a leading `'`.
- **Weekends don't break the streak** always skips Saturday and Sunday, also where the system region has another weekend (Friday–Saturday in the UAE).
- Plugging in or unplugging a display, docking or changing the resolution during a break no longer blanks the break screen for a couple of seconds: the tip, countdown and buttons stay in place.
- Settings → Keyboard Shortcuts no longer records ⌘ alone with a letter, digit or symbol (⌘S, ⌘N, ⌘K, …), which took that command from every app; add ⌃ or ⌥, or use a function key.
- A shortcut that can't act (such as Add 5 Minutes at the 180-minute limit) shows its banner only when notifications are on, and beeps when they are off or macOS blocks them.

## 3.7

### Added

- Settings → Alerts & Sound → **Wait during calls and video** (off by default): while another app keeps the display awake, such as a Zoom, Meet or Teams call or screen sharing in a normal window, the break screen waits until it stops instead of covering the call; the notification still arrives. A video playing also counts.
- **Undo Last Session** in Settings → Statistics removes only the focus session recorded last (after asking, with its label, time and minutes); if another session is recorded while you're asked, nothing is deleted, so one pomodoro counted by mistake no longer means resetting all statistics. A session from the current cycle also comes off the cycle dots, so the long break still comes after the real fourth pomodoro.

### Fixed

- Shortcuts **Add Time** now returns the minutes it added (0 when nothing is running or the session is at the 180-minute limit), so a shortcut can check whether it worked.
- The notification at the end of a break offers only **Start Next** when focus waits to be started; its **Skip** button jumped over the focus session to another break.
- A label typed after pressing Start is now saved with that focus session when it began without one; once a session has a label, the field's tooltip says edits apply from the next session.
- In Vietnamese, the "Last 7 days / Last 30 days" caption, the shortcut recorder hint and the VoiceOver value of the Settings button are now translated.
- README and the Daily goal tooltip now say a session that runs past midnight counts for the day it ends.
- The "daily goal reached" notification shows again when you raise the goal and reach it the same day, or reach it again after Reset Statistics.
- A timer left idle overnight now shows the fresh focus cycle on wake, at midnight and when the popover opens, instead of the old break that Start would not run.
- After undoing the session that reached the daily goal, the next pomodoro that reaches it again shows the "goal reached" notification.
- A focus session paused in the evening and skipped (or recorded with Record and Reset) the next morning now counts for the day and hour it ran, not for the morning, so Today, the daily goal, the streak, By hour and the CSV export stay right.
- After the Mac slept through the night in the middle of a focus session (or a postponed break), the menu bar now shows a fresh focus session at full length, so Start runs what you see instead of a leftover break from last night. The session that ended is still counted in History.

## 3.6

### Added

- Settings → Statistics → **Weekends don't break the streak** (off by default, shown with a daily goal): a Saturday or Sunday that misses the goal is skipped instead of resetting the streak; one that meets it still counts. With it on, the streak reaches back over the kept 90 days only, not the streak saved from older history.
- Settings → Statistics → **By hour**: a small 24-column chart of your focus minutes per hour of the day over the chosen 7 or 30 days, with "Most focused: 9 – 10 AM" below it. A session over the hour is split between both hours. Hovering a column, or VoiceOver, gives its hour and minutes.
- Settings → Automation → **Auto-pause when I'm away** (Off, 3, 5 or 10 minutes; off by default): leave the desk without locking and a running focus session pauses after that long without keyboard, mouse or trackpad input. The minutes away don't count, so History stays honest. With **Resume when I'm back** on (it now works with this setting too), the session continues when you use the Mac again.
- Settings → Statistics shows your record goal streak under the current one, e.g. "Best: 12 days in the last 90 days", when it is longer than the current streak.
- The break screen shows today's progress under the tip, as in the menu bar popover: "Today: 3/8 pomodoros · 75 min · Streak: 5 days" (only the pomodoros without a daily goal; hidden before your first pomodoro of the day). VoiceOver reads it as one line.
- Settings → Automation → **Resume when I'm back** (off by default, needs "Pause when the Mac sleeps or the screen locks"): a focus session paused by sleep or the lock continues a moment after you unlock the screen or wake the Mac. A session you paused yourself, or one paused for over four hours, stays paused.
- App Store release notes for this version in `docs/whats-new/` (English and Vietnamese), including Resume when I'm back and the fresh cycle after a long pause; a test keeps them under the 4000-character store limit with the same items in both languages.
- Global shortcut **Add 5 Minutes** (⌃⌥E, off by default; turn it on in Settings → Keyboard Shortcuts): adds 5 minutes to the running or paused session from any app, like +5 min.
- Settings → Statistics → **Export all (90 days)…** saves one row per day for the whole kept history, not only the 7 or 30 days on screen. Daily CSV file names now say the period: `TimeMate-statistics-7d-<date>.csv`, `-30d-` or `-all-`.
- Settings → Statistics → **Daily average** and **Best day** under the period total: your focus minutes per day over the chosen 7 or 30 days, and the day with the most pomodoros (the latest one on a tie). Both are hidden while the period has no focus session.
- **Shortcuts: Start Focus with Label and Add Time**: start a session with what you are working on (it fills "What are you working on?"; a running or paused session keeps its label), or add 1–60 minutes to the running or paused session (default 5, also restarts a finished break). Ask Siri "Start focus with a label in TimeMate" or "Add time in TimeMate".
- Settings → Statistics → **By label**: focus time per "What are you working on?" label over the chosen 7 or 30 days — your five longest labels (same label in other letter case counts once), then **Other** and **No label**. VoiceOver reads each row as "label, N minutes".
- **Recent labels**: a small chevron next to "What are you working on?" opens a menu with the labels of your last focus sessions (up to 8, newest first, same label in other letter case listed once). Pick one to fill the field, or choose **Clear label**.
- **Menu bar tooltip**: hovering the menu bar item shows the session and the time left (e.g. "Focus, 12 minutes, 34 seconds remaining"), also in the icon-only and minutes-only styles, without opening the popover.
- **+5 min for focus**: a small button under the popover controls adds five minutes to a running or paused focus session when you are in the flow, instead of letting it ring and starting over. The longer length is what the history and statistics record. Breaks are still extended from the break screen.
- Settings → Statistics → **Export sessions CSV…** saves each completed session of the last 90 days as `start,end,kind,minutes,label` (ISO 8601 times, with your "What are you working on?" label) for timesheets and invoices. The daily Export CSV is unchanged.
- Settings → Appearance → **Menu bar time** replaces "Hide time in menu bar" with three
  choices: minutes and seconds ("12:34"), **minutes only** ("13m", rounded up, a compact
  item for crowded menu bars that also wakes the app only once a minute) or icon only. If you had
  hidden the time, it starts as icon only. VoiceOver still reads minutes and seconds.
- **What are you working on?**: an optional one-line label in the popover during focus
  sessions. It is saved with each completed focus session in the history and shown in the
  "session complete" notification; it stays until you change it. Older history files load as
  before.
- **Goal streak**: Settings → Statistics shows "Streak: N days", the days in a row that met your daily goal (also beyond the 90 days of kept history; today not done yet doesn't break it). The popover shows it too under the goal progress bar (hidden when it is 0 or the goal is off), and the Shortcuts action **Get Today's Progress** says it.
- Settings → Automation: **Auto-start next session** is now two switches, **Auto-start breaks** and
  **Auto-start focus**, so breaks can run by themselves while you decide when to get back to
  work (or the other way round). Until you change them, both follow your old setting.
- Keyboard shortcuts in the popover: **Space** starts/pauses (not while typing in a duration
  field), **⌘,** opens or closes Settings, **⌘→** skips the session and **⌘R** resets it. Every
  button now has a tooltip, and VoiceOver reads the gear as "Settings" (expanded/collapsed).
- **Restart** asks for confirmation while a session is in progress.
- Settings → Statistics shows the last 7 days (pomodoros and focus minutes per day) with the
  period's total and the change against the previous 7 days. A **7 days / 30 days** switch
  (remembered) shows 30 days as a compact bar strip with the total and the change against the
  previous 30 days, e.g. "+4 pomodoros (+12%), +100 min"; the comparison is hidden when the
  previous period is empty. **Export CSV…** saves the chosen period as `date,pomodoros,minutes`,
  one row per day (7 rows for 7 days, 30 for 30 days).
- Settings → Automation → **Pause when the Mac sleeps or the screen locks** (off by default):
  a running session pauses when the Mac sleeps, the display turns off or the screen locks, and
  stays paused until you resume it, so a lunch break no longer counts as a pomodoro. With it
  off, nothing changes: the session keeps counting while the Mac sleeps.
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
- A **Get Today's Progress** Shortcuts action (Siri: "Today's progress in TimeMate") that
  returns the pomodoros completed today and says e.g. "Today: 3 of 8 pomodoros, 75 minutes";
  use it to turn off a Focus mode once the daily goal is reached.
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
- Today's statistics: the popover shows "Today: N pomodoros · X min" for completed
  focus sessions. Completed sessions (skipped ones don't count) are saved for 90 days
  and survive restarts; Settings → Statistics → "Reset Statistics" clears them.
- Unit test suite (`TimeMateTests`) covering the Pomodoro state machine, statistics,
  notifications, the break screen and the saved session. The timer now takes its
  `UserDefaults` and clock through its initializer, and settings keys live in one shared
  `SettingsKey` enum.
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
  by default). The popover shows "Today: 3/8 pomodoros" with a progress bar, the 7-day and
  30-day statistics mark the days you met it, the CSV export gets a `goal_reached` column, and
  a notification tells you once a day when you reach it.

### Changed

- The popover's "Today" line (goal progress, streak, VoiceOver label) is built by one tested helper; what it shows and says is unchanged.
- **Break screen at rest while waiting**: once a break is over and the screen waits for **Continue Work**, the cat stands still and the clock updates once a minute, so a break screen left up during lunch or a meeting no longer keeps the Mac busy. The cat still plays during the break.
- The break screen tests check the full-screen fallback poll directly (it runs, and stops when the break ends) instead of waiting on fixed delays, so the test suite runs about 7 seconds faster; behaviour is unchanged.
- The menu bar item's VoiceOver label rules (follow the timer only while VoiceOver is on, post the label only when it changes) are now covered by unit tests; behaviour is unchanged.
- While the break screen waits for a full-screen app, it now looks again when you switch Spaces or apps (and every 30 s as a fallback) instead of checking the windows every 5 s, saving battery during long full-screen breaks.
- Leaving a video's full screen inside the same app (YouTube in Safari, QuickTime) now brings the waiting break screen within about 2 seconds instead of up to 30 s: it looks again once the full-screen animation has ended and shortly after a click.
- Typing a session label or dragging the volume slider no longer makes the app re-check the break screen and tick mode; only the settings that matter trigger it.
- The menu bar time redraws once per update instead of twice (measured: 2 updates per tick
  before, 1 now, none when the shown time doesn't change), using less energy all day.
- Toggling the break screen setting in Alerts & Sound now immediately shows or hides
  the break screen during an active break.
- Uses less energy during breaks: only the countdown and skip counter re-render every
  second instead of redrawing the entire break screen and animations on all displays.
- The end-of-session notification now says what comes next: "Next: Short Break · 5 min", or
  "Short Break started · 5 min" when the next session starts by itself. In that case it has no
  **Start Next** button (only **Skip**), since the next session is already running.
- Under the hood: the session order, break extend/postpone and restore-after-relaunch rules moved
  out of the timer into small tested pieces; behaviour is unchanged.
- TimeMate no longer opens its popover and takes focus when it starts at login; it still
  opens on the first launch and when you open the app yourself. No Dock icon flashes at launch.
- Uses less energy: the countdown ticks every second only while you can see it (seconds in the
  menu bar, popover open, break screen, VoiceOver running), once a minute with minutes only,
  and otherwise the app wakes once when the session ends.
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

- The tooltip of **Auto-pause when I'm away** no longer says watching a video counts as away: a call or video that keeps the display awake keeps the session running.
- Settings → Statistics: the daily average now counts from your first day with data, so four days of 100 minutes show 100 min, not 57; the change against the previous period is hidden until your history covers that whole period.
- Reset no longer throws away a focus session that ran past half without asking: the popover and menu bar menu offer **Record and Reset** or **Reset Without Recording**, and the Reset shortcut and Shortcuts action record it, like Skip.
- Auto-pause when I'm away works again while a keep-awake utility (caffeinate, Amphetamine, KeepingYouAwake, Lungo, Caffeine, Theine) runs; only calls and videos keep the session going.
- **Auto-pause when I'm away** no longer pauses a focus session during a video call or while a video plays: when another app keeps the display awake, you are watching, not away.
- Skipping a focus session after half of it ran now records the time you focused in History, Today, the daily goal and Statistics, as it already counted in the cycle. A focus session skipped earlier still records nothing.
- "+5 min" and the Shortcuts "Add Time" action no longer stretch a session past 180 minutes (the longest length in Settings → Durations): only the minutes that fit are added, and at the limit Shortcuts answers "Already at the 180-minute limit".
- At the 180-minute limit, "+5 min" in the popover and on the break screen is dimmed and says why ("Already at the 180-minute limit", also read by VoiceOver), and the Add 5 Minutes shortcut shows that message instead of doing nothing.
- A session paused overnight (or for over 4 hours) no longer resumes the old cycle: it keeps its time left but starts a fresh cycle, so yesterday's pomodoros don't end it in a long break.
- **Export sessions CSV…** now writes when a paused session really started; it used to show the end minus the session length (a session started at 09:00, paused 09:10–09:40 and done at 10:05 showed 09:40). Sessions recorded before this update keep their old start.
- Settings → Durations → **Cycles** shows the number of focus sessions the timer really uses (e.g. 8, not an out-of-range 12 stored in defaults). VoiceOver reads it as "4 focus sessions" with a hint, in English and Vietnamese.
- **Skip delay on the break screen**: pressing **+5 min** no longer counts as a passing second, so it cannot unlock **Skip Break** before the skip delay is over.
- **Reset Statistics** now also deletes the backup of an unreadable history file (`session-history.corrupt-<date>.json`), so no old session label is left behind.
- **Daily goal notification after sleep**: when the session that reaches your daily goal ends while the Mac sleeps or TimeMate is closed, "Daily goal reached" now shows on wake or at the next launch (still once a day) instead of never.
- **30-day bar strip tooltip**: hovering a column now shows the full day in your language, e.g. "Monday, March 9: 4 pomodoros, 100 minutes, goal reached", instead of a bare "Mon 9: 4".
- **Export CSV with a Buddhist or Japanese calendar**: the `date` column and the file name now use Gregorian years (`2026-10-29`, not `2569-10-29` or `0008-10-29`), like the sessions export, so spreadsheets read them as dates.
- **Working past midnight**: a short break across midnight no longer resets the long-break cycle, so pomodoros at 23:45 and 00:05 still lead to your long break. The cycle starts over on a new day only after more than an hour without a session (or more than 4 hours on the same day).
- **Shortcuts in Vietnamese**: the **Start Focus** action and its description, and the description of **Start Focus with Label**, now show in Vietnamese instead of English.
- **Session lengths stored outside Settings**: a huge length set with `defaults write` or left in a damaged preferences file no longer crashes TimeMate at every launch. Stored lengths now run between 1 minute and 24 hours, and Settings → Durations shows the length the timer actually uses.
- **Export CSV**: the oldest day, 90 days back, now counts every session of that day instead of only the ones after the current time of day, so its pomodoros, minutes and `goal_reached` match the streak and the sessions collected that day.
- **Shortcuts: Start Timer, Start Focus, Pause Timer, Skip Session and Reset Timer** now say where the timer is after they run (e.g. "Short Break, not started, 1 min"), instead of only "Done". Pause Timer when nothing runs says so too.
- **Shortcuts: Start Focus** (new) and **Start Focus with Label**, and Siri "Start a focus session in TimeMate", now start a focus session when the timer waits on a break that has not started (Auto-start breaks off), instead of running the break. The finished pomodoro still counts once. **Start Timer** still starts the break.
- VoiceOver: the break screen window is named "Break" instead of an untitled window, and each Settings section title is a heading, so the rotor can jump between sections.
- Keyboard Shortcuts: a turned-off shortcut no longer blocks its combination, so ⌃⌥R can be recorded for Skip while Reset is off. Turning on a shortcut whose combination another one uses is refused with "Already used by … Change or turn off that shortcut first."
- **Continue Work** after a break screen left waiting overnight (or over 4 hours) now starts a fresh cycle on focus, so the morning's first pomodoro no longer ends in a long break.
- Shortcuts → **Add Time** now says what happened: "Added 5 minutes", or "No session to extend" when the timer is idle or the break is postponed, instead of finishing silently as if time was added.
- Settings → Keyboard Shortcuts: keypad keys and F13–F20 now show their name (e.g. "⌃⌘Keypad 1", "⌃⌥F15") instead of a number like "#83". VoiceOver says arrow, Return, Tab, Delete, Escape, Home, End and Page Up/Down keys by name ("Control Left Arrow") instead of reading the symbol.
- A notification macOS refuses to show (for example notifications turned off for TimeMate) is now logged in Console.app (TimeMate, category `app`) instead of failing silently, so a missing "session complete" or daily goal banner can be traced.
- Break screen: with several displays every screen shows the same relaxation tip, and it stays the same when a display is connected or removed during the break. Each new break picks a new tip.
- Settings → Durations: an entry that can't be saved (empty, not a whole number, under 1 or over 180 minutes) now shows a warning sign next to the red text and its tooltip says what is wrong. VoiceOver reads the problem and that leaving the field keeps the saved length.
- Settings → Durations: a very long number (e.g. 99999999999999999999) is now reported as too long instead of "Not a whole number", and VoiceOver says "keeps 1 minute" rather than "1 minutes". Shortcuts shows "Add 1 minute" for Add Time.
- **Reduce Motion in the popover**: with Reduce Motion on (System Settings → Accessibility → Display), the progress ring, the Settings chevron and the long-break cup now change without animating, like the break screen already did.
- **Readable text on a custom background**: the popover now picks dark or light text and controls from the background color you chose, so a white background in Dark Mode (or a black one in Light Mode) no longer hides the text. Mostly transparent colors keep the system appearance.
- The scheduled "session complete" notification now follows settings changed during a session (auto-start, the next session's length, the long break interval), so it no longer says "Next: Short Break" when the break starts by itself or runs longer.
- Break screen with several displays: VoiceOver reads the buttons and countdown only on the screen you work on instead of once per display, and announces "Break over. Continue Work to start focusing." when the break ends.
- Break screen: the skip countdown now reads "Skip available in 5 s" ("Bỏ qua sau 5 giây"), so VoiceOver announces the unit.
- Menu bar: the time text no longer turns white while a session runs, so it stays readable on a light menu bar.
- Skipping a Focus session before half of it has passed (for example a mis-clicked Start) no longer counts it towards the long break, so the cycle dots match Today and the history. Skipping later still counts it, as before; this also applies to the Skip shortcut and the Skip action in Shortcuts.
- The long-break cycle no longer carries over to the next day: when you start (or open TimeMate) with the timer idle and your last session was on an earlier day or more than 4 hours ago, the cycle begins again at focus, so three pomodoros last night no longer make this morning's first one end in a long break. A running or paused session keeps its cycle.
- Battery: while the display is off or the screen is locked and the Mac stays awake, the timer no longer ticks every second (even with the menu bar showing minutes and seconds); it catches up the moment the screen is back.
- **Reset** (⌃⌥R shortcut or the Shortcuts action) on a finished break that waits on the break screen now returns to a fresh focus session instead of starting the break over.
- The "session complete" notification no longer goes missing when TimeMate has quit or crashed, or is late because the Mac slept: it is scheduled for the end of the session and still shows once, on time.
- **Reset All Settings** now also turns off Start at Login, so the Mac no longer opens TimeMate at login after a reset.
- The menu bar tooltip showed the time from the last update, so in the icon-only and minutes-only styles it stayed at the full session length while you worked; it now shows the time left when you hover.
- Settings → Statistics → 30 days: VoiceOver now reads the bar strip day by day ("Monday, October 20: 4 pomodoros, 100 minutes, goal reached") instead of skipping it.
- **"Pause on sleep" is for focus sessions only**: when the Mac sleeps or the screen locks a running break no longer pauses — it keeps counting, still ends on time (silently if the wake comes more than 5 minutes late) and the break screen comes back when you unlock, so a lid-close during lunch no longer freezes the break until you press Resume. A running focus session still pauses, and with the setting off nothing changes.
- Vietnamese Settings labels: "Hiển thị vòng tiến trình" (was misspelled), "Giữ Mac không ngủ" and "Giữ cửa sổ luôn ở trên" now say what they do, and "Start at Login" has one translation ("Khởi động cùng máy") instead of two conflicting ones.
- A focus session keeps the "What are you working on?" label it started with: typing the next task before the bell (or while paused, or across a relaunch) no longer relabels the session that just ended in the history, the sessions CSV and the "session complete" notification. The field stays editable; the new text applies to the next session.
- The daily goal notification still comes the same day if notifications were off when the goal was reached and you turn them on before the next session ends.
- Pressing Esc twice on the break screen no longer skips a break before the **Skip button delay** has passed (the Skip button and the global shortcut ⌃⌥S / Shortcuts behave as before); the "Press Esc twice to skip" hint now shows only when Esc works.
- The minutes-only menu bar time is localized ("13 ph" in Vietnamese instead of "13m").
- Connecting or disconnecting a display (or Sidecar/AirPlay) during a break no longer restarts the "Skip available in N" countdown or stops the break screen's clock, and no longer brings back a break screen that was already closing after the break ended or was skipped.
- Global keyboard shortcuts keep working after changing the language or resetting all settings
  (the app restart briefly ran two copies, and the new one lost ⌃⌥P/⌃⌥S and Settings blamed
  another app). Shortcuts that are taken are tried again a few seconds after launch and whenever
  TimeMate comes to the front; closing the popover while recording a shortcut turns them back on.
- With the Dock icon shown, **TimeMate → Settings…** (⌘,) opens the popover on Settings instead of a blank window.
- VoiceOver reads each shortcut button as "Start / Pause shortcut, Control Option P" instead of "⌃⌥P", and the background color well as "Background Color".
- Settings → Keyboard Shortcuts no longer accepts a combination another TimeMate action already uses or a bare ⌘ shortcut macOS needs (⌘C, ⌘V, ⌘X, ⌘Z, ⌘A, ⌘Q, ⌘W, ⌘H, ⌘, ⌘Space, ⌘Tab). It now says "Already used by <action>" or "Reserved by macOS" instead of blaming another app.
- **Break screen battery use**: while a break counts down, the break screen no longer runs a second one-second clock next to the timer, so the Mac wakes up half as often during breaks. The clock still runs when the break is paused or waiting for Continue Work.
- **Skip while idle** no longer counts a focus session you never started: the cycle dots and VoiceOver ("1 of 4 focus sessions done") stay put and the long break does not come early. Skipping a running or paused focus session still counts it.
- **Exported CSV files** (daily and sessions) now start with a UTF-8 byte order mark, so Excel shows Vietnamese and other accented labels correctly instead of garbled text.
- **Auto-start focus** now works when the break screen is off (or held back by a full-screen app): a finished break no longer waits silently for "Continue Work". With the break screen showing and "Keep break screen open until continued" on, nothing changes. Settings → Automation explains it under Auto-start focus.
- The break screen's hints ("Press Esc twice to skip", "Skip available in…", Postpone) are no longer dimmed to 40–50%, and turn fully opaque with Increase Contrast. VoiceOver now reads the seconds of the "Skip button delay" stepper.
- One unreadable record in the session history (for example from a newer or older version)
  no longer wipes all your history and goal streak: that record is skipped and the rest is kept.
  Before the next session is saved without it, the original file is kept as
  `session-history.corrupt-<date>.json` (the latest one only), so the skipped record isn't lost.
- **Auto-start on launch** only starts a focus session. If the session restored from last time
  is a break, TimeMate waits for you instead of opening the break screen when the app starts.
- VoiceOver reads the popover clock as "Time remaining" with a spelled-out value such as "24
  minutes, 30 seconds" (like the menu bar and the break screen), with or without the progress ring.
- **Start Next** / **Skip** on an old "session complete" notification no longer act on the
  session you are running: TimeMate removes that notification from Notification Center when you
  start, skip, reset or restart, and a new one replaces the previous.
- Waking the Mac from a long sleep no longer rings the alarm or shows a "session complete" notification for a session that ended more than 5 minutes ago; the session just ends quietly.
- Closing the lid or quitting during a session no longer greets you with a full-screen break
  that started hours ago: a session that ended more than 5 minutes before you wake the Mac or
  open TimeMate still counts in your statistics, but the next session waits for Start (no break
  screen). Within those 5 minutes auto-start works as before.
- The break screen no longer rescans the system window list on every unrelated settings write
  (timer state, alarm volume, colors); dragging the volume slider is smooth again during a break.
- Start at Login: if macOS refuses to register or remove the login item, the switch goes back
  to its real state and shows the reason with an Open System Settings button; it also updates
  when you change the login item in System Settings and return to TimeMate.
- A hand-typed background color is only accepted as 3, 6 or 8 hex digits; anything else keeps
  the previous color instead of turning into a different one. Color to hex now rounds
  instead of truncating.
- Changing a session length while the break screen is held open (Continue Work) no longer
  makes the Continue Work button disappear.
- Settings → Language now shows "System Default" when you have not picked a language, and the
  picker is named for VoiceOver.
- If TimeMate cannot relaunch itself after a language change or Reset All Settings, it now
  tells you to reopen it instead of failing silently; a failed notification permission request
  is logged.
- About opens the TimeMate page in your language (Vietnamese or English); the Keep Mac awake
  help text now says it applies during a focus session.
- Reset All Settings no longer drops the running session or the daily-goal notification
  state: the session carries on after the restart and the goal notification isn't sent twice.
- The break screen's clock stops when the screen is hidden, and the Esc and screen-change
  listeners are removed when they are not needed.
- When a break has ended and waits on the break screen, the popover's main button now
  reads "Continue Work" and starts the next focus session instead of running the break
  again.
- Changing a session length in Settings → Durations updates the idle timer right away
  instead of on the next Start. Clicking a TimeMate notification opens the popover.
- English statistics use singular and plural forms: "Today: 1 pomodoro" instead of
  "1 pomodoros" (also the period total, the change against the previous period and VoiceOver's
  "1 minute"). Vietnamese is unchanged.
- An unreadable statistics file no longer gets overwritten and lose its sessions: it is
  kept as `session-history.corrupt-<date>.json` next to it (the latest one only) and
  statistics start over.
- A broken "Cycles" value in the preferences (below 1 or above 8) no longer crashes the
  popover; it is treated as 1–8.
- "Today" in the popover and the Statistics days roll over at midnight and after a change of
  the system time or time zone; setting the clock no longer cuts short or stretches a running
  session.
- Quitting, updating or a crash no longer loses the session: a running timer keeps
  counting down after relaunch, a paused one stays paused, and the pomodoro count is
  kept. A session that ended while TimeMate was closed is added to the statistics on
  the day it ended and the next session follows (started only if auto-start is on
  for it and it ended at most 5 minutes ago), without a late alarm or notification.
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
  second, and the menu bar item updates in place when its time display is changed.
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
