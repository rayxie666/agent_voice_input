import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A SwiftUI text-field-like control that captures the next keystroke and
/// reports it back as a KeyCombo. Click to focus, press the desired chord,
/// click outside (or press Esc) to cancel.
struct HotkeyRecorderField: NSViewRepresentable {
    @Binding var combo: KeyCombo

    func makeNSView(context: Context) -> RecorderField {
        let field = RecorderField()
        field.onChange = { combo = $0 }
        field.combo = combo
        return field
    }

    func updateNSView(_ nsView: RecorderField, context: Context) {
        nsView.combo = combo
    }
}

final class RecorderField: NSView {
    var combo: KeyCombo = .recordRaw { didSet { needsDisplay = true } }
    var onChange: ((KeyCombo) -> Void)?
    private var capturing = false {
        didSet { needsDisplay = true; toolTip = capturing ? "Press a key combination…" : nil }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 140, height: 24) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        capturing = true
    }

    override func resignFirstResponder() -> Bool {
        capturing = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard capturing else { return super.keyDown(with: event); }
        if event.keyCode == kVK_Escape {
            capturing = false
            return
        }
        let mods = carbonModifiers(from: event.modifierFlags)
        // Ignore if no modifiers (would clash with normal typing).
        if mods == 0 {
            NSSound.beep()
            return
        }
        combo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)
        onChange?(combo)
        capturing = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = capturing
            ? NSColor.controlAccentColor.withAlphaComponent(0.15)
            : NSColor.controlBackgroundColor
        bg.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: 5, yRadius: 5)
        path.fill()
        (capturing ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = capturing ? "按下键位组合…" : combo.displayString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let origin = NSPoint(x: (bounds.width - size.width) / 2,
                             y: (bounds.height - size.height) / 2)
        str.draw(at: origin)
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        return m
    }
}
