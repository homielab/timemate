//  Created by homielab.com

import Foundation

/// Calls `onChange` on the main thread when one of `keys` changes in `defaults`.
///
/// `UserDefaults.didChangeNotification` fires on every write (timer snapshot,
/// volume, the label typed in the popover...), so the observer remembers the
/// values of its keys and only reports a real change in one of them. It is the
/// one place that listens for the notification.
final class DefaultsObserver {
  private let defaults: UserDefaults
  private let keys: [String]
  private let onChange: () -> Void
  private var snapshot: NSArray
  private var token: NSObjectProtocol?

  init(defaults: UserDefaults, keys: [String], onChange: @escaping () -> Void) {
    self.defaults = defaults
    self.keys = keys
    self.onChange = onChange
    self.snapshot = Self.snapshot(of: keys, in: defaults)
    token = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification, object: defaults, queue: nil
    ) { [weak self] _ in
      // A write from a background thread hops to main once; the comparison and
      // the handler run there.
      if Thread.isMainThread {
        self?.check()
      } else {
        DispatchQueue.main.async { self?.check() }
      }
    }
  }

  deinit {
    if let token { NotificationCenter.default.removeObserver(token) }
  }

  private func check() {
    let current = Self.snapshot(of: keys, in: defaults)
    guard !current.isEqual(snapshot) else { return }
    snapshot = current
    onChange()
  }

  private static func snapshot(of keys: [String], in defaults: UserDefaults) -> NSArray {
    keys.map { defaults.object(forKey: $0) ?? NSNull() } as NSArray
  }
}
