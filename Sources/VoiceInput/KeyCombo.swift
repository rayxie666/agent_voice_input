import AppKit
import Carbon.HIToolbox

/// A user-configurable global hotkey: a non-modifier key + a set of modifier flags.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32           // Carbon virtual key code
    var modifiers: UInt32         // Carbon modifier mask (cmdKey, optionKey, ...)

    static let recordRaw = KeyCombo(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | optionKey)
    )

    static let recordPolish = KeyCombo(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | optionKey | shiftKey)
    )

    /// Default ⌥P — polishes whatever was just dictated (no new recording).
    static let polishLast = KeyCombo(
        keyCode: UInt32(kVK_ANSI_P),
        modifiers: UInt32(optionKey)
    )

    /// Pretty representation, e.g. "⌃⌥Space".
    var displayString: String {
        var parts = ""
        if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { parts += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { parts += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { parts += "⌘" }
        parts += KeyCombo.keyName(for: keyCode)
        return parts
    }

    static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space:           return "Space"
        case kVK_Return:          return "Return"
        case kVK_Escape:          return "Esc"
        case kVK_Tab:             return "Tab"
        case kVK_Delete:          return "Delete"
        case kVK_F1:  return "F1";  case kVK_F2:  return "F2"
        case kVK_F3:  return "F3";  case kVK_F4:  return "F4"
        case kVK_F5:  return "F5";  case kVK_F6:  return "F6"
        case kVK_F7:  return "F7";  case kVK_F8:  return "F8"
        case kVK_F9:  return "F9";  case kVK_F10: return "F10"
        case kVK_F11: return "F11"; case kVK_F12: return "F12"
        case kVK_LeftArrow:        return "←"
        case kVK_RightArrow:       return "→"
        case kVK_UpArrow:          return "↑"
        case kVK_DownArrow:        return "↓"
        default:
            // Try to map via current keyboard layout for printable keys.
            return printableName(forKeyCode: keyCode) ?? "Key\(keyCode)"
        }
    }

    private static func printableName(forKeyCode keyCode: UInt32) -> String? {
        guard let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?
                .takeRetainedValue() else { return nil }
        let layoutData = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData)
        guard let data = layoutData else { return nil }
        let layoutPtr = unsafeBitCast(data, to: CFData.self)
        let bytes = CFDataGetBytePtr(layoutPtr)
        let keyboardLayout = bytes!.withMemoryRebound(
            to: UCKeyboardLayout.self, capacity: 1) { $0 }

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var realLen = 0
        let status = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &realLen,
            &chars
        )
        guard status == noErr, realLen > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: realLen).uppercased()
    }
}
