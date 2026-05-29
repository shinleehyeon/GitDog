// Gipet — status-item-anchored window.
//
// Git Streaks doesn't use a plain NSPopover (which repositions far from the
// anchor when its content is wide). Its ChouTiUI framework uses a custom
// borderless window placed directly under the status item — symbols seen in
// the binary: StatusItemWindow, DetachableWindowStatusItem,
// WindowContentViewController, BasePopover, leftStatusItemWindow.
//
// This reproduces that behaviour with stock AppKit: a borderless, non-
// activating panel whose frame is computed from the status button's screen
// position and clamped to the visible screen.

import AppKit

final class StatusItemWindow: NSPanel {
    init(contentView: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Rounded container that clips the SwiftUI content.
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        contentView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: container.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        self.contentView = container
    }

    // Borderless panels don't become key by default; allow it so the username/
    // token text fields are editable.
    override var canBecomeKey: Bool { true }

    /// Place the window directly below `button`, horizontally centred on it and
    /// clamped to the button's screen.
    func anchor(below button: NSStatusBarButton, gap: CGFloat = 6) {
        guard let buttonWindow = button.window else { return }
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero

        // Status button's rect in screen coordinates.
        let inWindow = button.convert(button.bounds, to: nil)
        let onScreen = buttonWindow.convertToScreen(inWindow)

        let size = frame.size
        var x = onScreen.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)

        var y = onScreen.minY - gap - size.height        // hang below the menu bar
        if y < visible.minY + 8 { y = visible.minY + 8 }

        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
