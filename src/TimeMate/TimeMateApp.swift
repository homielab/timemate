import SwiftUI

@main
struct TimeMateApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    // The real settings live in the popover; an empty Settings scene would open a blank window.
    Settings {}
      .commands {
        CommandGroup(replacing: .appSettings) {
          Button("Settings…") { appDelegate.openSettings() }
            .keyboardShortcut(",", modifiers: .command)
        }
      }
  }
}
