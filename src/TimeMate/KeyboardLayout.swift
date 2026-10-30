//  Created by homielab.com

import Carbon

/// Reads the current keyboard layout, so shortcut labels show the character
/// printed on the user's key (Z on AZERTY where US has W) instead of the US one.
enum KeyboardLayout {
  /// The character `keyCode` types without modifiers, nil when it types none
  /// or the layout has no Unicode data.
  static func character(for keyCode: UInt32) -> String? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
      let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    var deadKeyState: UInt32 = 0
    var length = 0
    var characters = [UniChar](repeating: 0, count: 4)
    let status = data.withUnsafeBytes { raw -> OSStatus in
      guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
        return OSStatus(paramErr)
      }
      return UCKeyTranslate(
        layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length,
        &characters)
    }
    guard status == noErr, length > 0 else { return nil }
    let text = String(utf16CodeUnits: characters, count: length)
    let visible = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    return visible.isEmpty ? nil : visible
  }
}
