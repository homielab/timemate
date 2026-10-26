//  Created by homielab.com

import AppKit
import SwiftUI

struct AppearanceSection: View {
  @EnvironmentObject var appDelegate: AppDelegate
  @Binding var showProgressCircle: Bool
  @Binding var backgroundColorHex: String

  @AppStorage(SettingsKey.hideMenuBarTime) private var hideMenuBarTime = false
  @AppStorage(SettingsKey.alwaysVisible) private var alwaysVisible = false

  var body: some View {
    SettingsSection(titleKey: "Appearance", systemImage: "paintbrush.fill") {
      SettingsToggleRow(titleKey: "Show Progress Circle", isOn: $showProgressCircle)
      SettingsToggleRow(titleKey: "Hide time in menu bar", isOn: $hideMenuBarTime)
        .onChange(of: hideMenuBarTime) { newValue in
          appDelegate.updateMenuBarWidth(hideTime: newValue)
        }
      SettingsToggleRow(titleKey: "Keep window on top", isOn: $alwaysVisible)
        .onChange(of: alwaysVisible) { newValue in
          appDelegate.setPopoverBehavior(alwaysVisible: newValue)
        }
      HStack {
        Text("Background Color")
        Spacer(minLength: 12)
        CustomColorPicker(hexColor: $backgroundColorHex)
          .fixedSize()

        Button {
          backgroundColorHex = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .accessibilityLabel(Text("Clear Background Color"))
      }
    }
  }
}

private struct CustomColorPicker: NSViewRepresentable {
  @Binding var hexColor: String

  func makeNSView(context: Context) -> NSColorWell {
    let colorWell = NSColorWell(style: .minimal)
    if #available(macOS 14.0, *) {
      colorWell.supportsAlpha = true
    }
    colorWell.action = #selector(context.coordinator.colorChanged(_:))
    colorWell.target = context.coordinator
    colorWell.color = NSColor(hex: hexColor) ?? .clear
    return colorWell
  }

  func updateNSView(_ nsView: NSColorWell, context: Context) {
    // An unparsable string keeps the color already shown instead of turning it clear.
    if let color = NSColor(hex: hexColor) {
      nsView.color = color
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  class Coordinator: NSObject {
    var parent: CustomColorPicker

    init(_ parent: CustomColorPicker) {
      self.parent = parent
    }

    @objc func colorChanged(_ sender: NSColorWell) {
      parent.hexColor = Color(sender.color).toHex() ?? ""
    }
  }
}
