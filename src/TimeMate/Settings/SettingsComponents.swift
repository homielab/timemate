//  Created by homielab.com

import SwiftUI

/// A titled group of settings: a small icon + caption header above a rounded card.
struct SettingsSection<Content: View>: View {
  let titleKey: LocalizedStringKey
  let systemImage: String
  private let content: Content

  init(titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content) {
    self.titleKey = titleKey
    self.systemImage = systemImage
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: systemImage)
          .font(.system(size: 11, weight: .semibold))
        Text(titleKey)
          .font(.system(size: 13, weight: .semibold))
      }
      .foregroundColor(.secondary)

      VStack(alignment: .leading, spacing: 12) {
        content
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
  }
}

/// A settings row with the label on the left and a switch pinned to the right,
/// so switches stay aligned across rows regardless of label length.
struct SettingsToggleRow: View {
  let titleKey: LocalizedStringKey
  @Binding var isOn: Bool

  var body: some View {
    HStack {
      Text(titleKey)
      Spacer(minLength: 12)
      Toggle(isOn: $isOn) { EmptyView() }
        .toggleStyle(.switch)
        .fixedSize()
        .accessibilityLabel(Text(titleKey))
    }
  }
}

/// A full-width row button with an optional icon that highlights on hover.
struct MenuItemButton: View {
  let title: LocalizedStringKey
  let systemImage: String?
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack {
        if let systemImage = systemImage {
          Image(systemName: systemImage)
            .font(.system(size: 14))
            .frame(width: 20)
        }
        Text(title)
        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .background(isHovering ? Color.secondary.opacity(0.2) : Color.clear)
      .cornerRadius(5)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovering = hovering
    }
  }
}
