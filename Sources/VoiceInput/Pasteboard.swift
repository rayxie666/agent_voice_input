import AppKit
import Carbon.HIToolbox

/// Inject `text` into whatever app currently has keyboard focus.
///
/// We synthesize Unicode keyboard events so the text lands directly in the
/// focused text field (like Apple's dictation), bypassing the user's clipboard
/// entirely. Falls back to a clipboard+⌘V path if Accessibility is denied.
enum Pasteboard {
    /// Serial queue so concurrent injection requests (e.g. multiple streaming
    /// chunks) don't interleave their keystrokes mid-character.
    private static let injectQueue = DispatchQueue(label: "voiceinput.inject")

    static func paste(_ text: String) {
        guard !text.isEmpty else { return }
        if hasAccessibility(prompt: false) {
            injectQueue.async { typeUnicode(text) }
        } else {
            // Best we can do without accessibility: leave it on the clipboard
            // so the user can ⌘V manually, and beep so they notice.
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            NSSound.beep()
        }
    }

    /// Streaming variant: type the chunk if Accessibility is granted, return
    /// false otherwise. Caller is expected to handle the no-permission case
    /// (we can't beep on every chunk during streaming — too noisy).
    @discardableResult
    static func injectIfAllowed(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        guard hasAccessibility(prompt: false) else { return false }
        injectQueue.async { typeUnicode(text) }
        return true
    }

    /// Send the string as a stream of synthetic Unicode keyDown/keyUp events,
    /// one user-visible grapheme per event with a perceptible delay. Reads as
    /// "the app is typing", which is the UX the user explicitly wants.
    /// 25ms ≈ 40 cps, fast-typing speed — visibly per-character but not slow.
    private static let perCharDelayMicros: useconds_t = 25_000

    private static func typeUnicode(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Iterate by Character so a Chinese char or an emoji each get one
        // event, even when the underlying utf16 representation is multi-unit.
        for ch in text {
            var units = Array(ch.utf16)

            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            units.withUnsafeMutableBufferPointer { ptr in
                down?.keyboardSetUnicodeString(
                    stringLength: ptr.count, unicodeString: ptr.baseAddress)
            }
            down?.post(tap: .cghidEventTap)

            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            units.withUnsafeMutableBufferPointer { ptr in
                up?.keyboardSetUnicodeString(
                    stringLength: ptr.count, unicodeString: ptr.baseAddress)
            }
            up?.post(tap: .cghidEventTap)

            usleep(perCharDelayMicros)
        }
    }

    /// Synchronously send `count` Backspace keystrokes to the focused app.
    /// Used by the in-place polish flow to delete the just-typed raw text
    /// before injecting the polished version. Caller is responsible for
    /// dispatching off the main thread — the per-key delay totals
    /// 2ms × count, which is fine for typical voice transcripts (under 200 chars)
    /// but would block UI for unboundedly long inputs.
    static func sendBackspaces(_ count: Int) {
        guard count > 0 else { return }
        guard hasAccessibility(prompt: false) else { return }
        injectQueue.sync {
            let src = CGEventSource(stateID: .combinedSessionState)
            let key = CGKeyCode(kVK_Delete)
            let tap = CGEventTapLocation.cghidEventTap
            for _ in 0..<count {
                CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)?.post(tap: tap)
                CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)?.post(tap: tap)
                usleep(2000)
            }
        }
    }

    /// True when the system trusts this app to post synthetic events. If false,
    /// the user must enable us in System Settings → Privacy → Accessibility.
    static func hasAccessibility(prompt: Bool = false) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts: CFDictionary = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Open System Settings on the Accessibility privacy pane AND ask the
    /// system to register us in that pane (the prompt:true variant). Without
    /// the prompt call, the app may not appear in the list until it tries to
    /// post a CGEvent — confusing for the user who's looking for it now.
    static func openAccessibilityPane() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts: CFDictionary = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }
}
