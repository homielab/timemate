import SwiftUI

@main
struct TimeMateApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    Settings {}
  }
}
