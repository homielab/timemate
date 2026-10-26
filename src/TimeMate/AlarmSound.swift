//  Created by homielab.com

import AppKit
import os

/// The sounds that play when a session ends: one after a focus session
/// (`SettingsKey.alarmSound`) and one after a break (`SettingsKey.breakEndSound`,
/// which follows the alarm sound until the user picks one). "None" plays nothing.
enum AlarmSound {
  /// Stored name of the "no sound" choice.
  static let none = "None"
  static let defaultName = "Glass"

  /// The system sounds in `/System/Library/Sounds`, found by `NSSound(named:)`.
  static let systemSounds = [
    "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr",
    "Sosumi", "Submarine", "Tink",
  ]

  /// Choices of the Settings pickers, "None" first.
  static let options = [none] + systemSounds

  /// The alarm sound saved in `defaults`.
  static func alarmSound(in defaults: UserDefaults) -> String {
    defaults.string(forKey: SettingsKey.alarmSound) ?? defaultName
  }

  /// The break-end sound saved in `defaults`, or the alarm sound when none was chosen.
  static func breakEndSound(in defaults: UserDefaults) -> String {
    defaults.string(forKey: SettingsKey.breakEndSound) ?? alarmSound(in: defaults)
  }

  /// The sound to play when a session of `type` ends.
  static func sound(afterCompleting type: SessionType, in defaults: UserDefaults) -> String {
    switch type {
    case .focus: return alarmSound(in: defaults)
    case .shortBreak, .longBreak: return breakEndSound(in: defaults)
    }
  }

  /// Plays the sound called `name` at `volume` (0…1). "None" plays nothing; a
  /// sound that can't be loaded is logged. Returns whether a sound started.
  @discardableResult
  static func play(
    _ name: String, volume: Float,
    load: (String) -> NSSound? = { NSSound(named: $0) }
  ) -> Bool {
    guard name != none else { return false }
    guard let sound = load(name) else {
      Logger.app.error("Could not load alarm sound \(name, privacy: .public)")
      return false
    }
    sound.volume = volume
    return sound.play()
  }
}
