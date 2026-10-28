//  Created by homielab.com

import SwiftUI

extension Color {
  init?(hex: String) {
    if let nsColor = NSColor(hex: hex) {
      self.init(nsColor: nsColor)
    } else {
      return nil
    }
  }

  func toHex() -> String? {
    return NSColor(self).toHex()
  }
}

extension NSColor {
  convenience init?(hex: String) {
    guard let (r, g, b, a) = NSColor.rgba(fromHex: hex) else {
      return nil
    }

    self.init(red: r, green: g, blue: b, alpha: a)
  }

  /// Parses `RGB`, `RRGGBB` or `RRGGBBAA` (optional leading `#`); anything else is nil.
  static func rgba(fromHex hex: String) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
    var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if digits.hasPrefix("#") { digits.removeFirst() }
    guard [3, 6, 8].contains(digits.count),
      digits.unicodeScalars.allSatisfy({ $0.isASCII && $0.properties.isASCIIHexDigit })
    else { return nil }
    if digits.count == 3 {
      digits = digits.map { "\($0)\($0)" }.joined()
    }
    guard let value = UInt64(digits, radix: 16) else { return nil }
    let hasAlpha = digits.count == 8
    let shift: UInt64 = hasAlpha ? 8 : 0
    func channel(_ index: UInt64) -> CGFloat {
      CGFloat((value >> (shift + (2 - index) * 8)) & 0xFF) / 255.0
    }
    let alpha: CGFloat = hasAlpha ? CGFloat(value & 0xFF) / 255.0 : 1.0
    return (channel(0), channel(1), channel(2), alpha)
  }

  /// WCAG relative luminance (0 = black, 1 = white) of a hex color, alpha ignored;
  /// nil when the hex doesn't parse.
  static func relativeLuminance(fromHex hex: String) -> CGFloat? {
    guard let (r, g, b, _) = rgba(fromHex: hex) else { return nil }
    func linear(_ c: CGFloat) -> CGFloat {
      c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
  }

  /// Whether dark text reads better than light text on this background: true above the
  /// luminance where black and white text have the same contrast ratio (about 0.179).
  /// nil when the hex doesn't parse or the color is mostly transparent (alpha < 0.5),
  /// so the system appearance shows through and decides.
  static func prefersDarkText(onBackgroundHex hex: String) -> Bool? {
    guard let (_, _, _, alpha) = rgba(fromHex: hex), alpha >= 0.5,
      let luminance = relativeLuminance(fromHex: hex)
    else { return nil }
    return luminance > 0.179
  }

  func toHex() -> String? {
    guard let srgbColor = self.usingColorSpace(.sRGB) else {
      return "#000000"
    }

    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    srgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)

    if a == 1.0 {
      return String(
        format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()),
        Int((b * 255).rounded()))
    } else {
      return String(
        format: "#%02X%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()),
        Int((b * 255).rounded()), Int((a * 255).rounded()))
    }
  }
}
