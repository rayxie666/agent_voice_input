import AppKit
import SwiftUI

/// Borderless, nonactivating floating panel that appears near the mouse cursor
/// after a raw dictation completes. Clicking the bubble triggers an in-place
/// AI polish of whatever was just typed.
@MainActor
final class PolishBubble {
    private let panel: NSPanel
    private var dismissTimer: Timer?
    private let onClick: () -> Void

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 0, height: 0),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isMovable = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // Stay across all spaces so the bubble doesn't disappear if the user
        // is mid-Mission-Control or on a fullscreen space.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
    }

    /// Show the bubble near the current mouse position. Auto-dismisses after
    /// `timeout` seconds. Re-showing while already visible just resets the
    /// position and timer.
    func show(timeout: TimeInterval = 8.0) {
        let host = NSHostingView(rootView: PolishBubbleView { [weak self] in
            self?.handleClick()
        })
        host.translatesAutoresizingMaskIntoConstraints = false
        let fitting = host.fittingSize
        let size = NSSize(width: max(110, fitting.width), height: max(34, fitting.height))
        panel.setContentSize(size)
        panel.contentView = host

        positionNearMouse(size: size)

        // .orderFront (not .makeKey) keeps focus in the user's target app —
        // so they can keep typing while the bubble is visible.
        panel.orderFrontRegardless()

        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) {
            [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    private func handleClick() {
        hide()
        onClick()
    }

    /// Place the bubble slightly down-right of the mouse, but keep it within
    /// the current screen so it isn't clipped at the edges.
    private func positionNearMouse(size: NSSize) {
        let mouse = NSEvent.mouseLocation  // bottom-left origin, screen coords
        var origin = NSPoint(x: mouse.x + 14, y: mouse.y - size.height - 8)

        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            origin.x = max(frame.minX + 4, min(origin.x, frame.maxX - size.width - 4))
            origin.y = max(frame.minY + 4, min(origin.y, frame.maxY - size.height - 4))
        }
        panel.setFrameOrigin(origin)
    }
}

private struct PolishBubbleView: View {
    let onClick: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .imageScale(.small)
                    .foregroundStyle(.yellow)
                Text("润色")
                    .font(.system(size: 12, weight: .semibold))
                Text("⌥P")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(hovering ? 0.95 : 0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(2)  // give shadow some breathing room
    }
}
