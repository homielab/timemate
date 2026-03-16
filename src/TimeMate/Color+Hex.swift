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
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

    var rgb: UInt64 = 0

    guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
      return nil
    }

    let length = hexSanitized.count
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat

    if length == 6 {
      r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
      g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
      b = CGFloat(rgb & 0x0000FF) / 255.0
      a = 1.0
    } else if length == 8 {
      r = CGFloat((rgb & 0xFF00_0000) >> 24) / 255.0
      g = CGFloat((rgb & 0x00FF_0000) >> 16) / 255.0
      b = CGFloat((rgb & 0x0000_FF00) >> 8) / 255.0
      a = CGFloat(rgb & 0x0000_00FF) / 255.0
    } else {
      return nil
    }

    self.init(red: r, green: g, blue: b, alpha: a)
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
      return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    } else {
      return String(
        format: "#%02X%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
    }
  }
}
