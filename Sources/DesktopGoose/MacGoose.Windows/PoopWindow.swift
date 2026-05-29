import AppKit
import CoreGraphics

final class PoopWindow: NSWindow {
    var onRemove: (() -> Void)?

    init(worldPosition: Vector2, worldHeight: CGFloat) {
        let size = CGSize(width: 28, height: 28)
        let frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces]
        ignoresMouseEvents = false
        contentView = PoopView(frame: frame)
        place(at: worldPosition, worldHeight: worldHeight)
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func place(at worldPosition: Vector2, worldHeight: CGFloat) {
        let x = CGFloat(worldPosition.x) - frame.width * 0.5
        let y = worldHeight - CGFloat(worldPosition.y) - frame.height * 0.5
        setFrameOrigin(CGPoint(x: x, y: y))
    }

    func dismiss() {
        onRemove?()
        orderOut(nil)
        close()
    }
}

private final class PoopView: NSView {
    private static let dropImagePath =
        "/Users/shinleehyeon/.cursor/projects/Users-shinleehyeon-Dev-Projects-gipet/assets/gitgit-ef053c9e-6397-4f62-bbe9-8287f9be2cce.png"
    private static let dropImage = NSImage(contentsOfFile: dropImagePath)

    override func draw(_ dirtyRect: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext else { return }
        let baseRect = bounds.insetBy(dx: 2, dy: 2)

        // Draw the base icon first, then blend with warm brown overlays so it
        // still reads as the original image but gets a "poop-ish" look.
        if let image = Self.dropImage {
            image.draw(in: baseRect)
            g.setBlendMode(.multiply)
            g.setFillColor(CGColor(red: 0.44, green: 0.27, blue: 0.13, alpha: 0.58))
            g.fillEllipse(in: baseRect)
            g.setBlendMode(.normal)

            // A couple of small lumps to sell the silhouette.
            g.setFillColor(CGColor(red: 0.34, green: 0.19, blue: 0.09, alpha: 0.90))
            g.fillEllipse(in: CGRect(x: baseRect.midX - 7, y: baseRect.midY + 1, width: 11, height: 8))
            g.fillEllipse(in: CGRect(x: baseRect.midX - 2, y: baseRect.midY + 6, width: 8, height: 6))

            // Tiny glossy highlight so it doesn't look flat.
            g.setFillColor(CGColor(red: 0.96, green: 0.90, blue: 0.75, alpha: 0.24))
            g.fillEllipse(in: CGRect(x: baseRect.minX + 6, y: baseRect.maxY - 11, width: 6, height: 3))
            return
        }

        // Fallback if image path is unavailable.
        g.setFillColor(CGColor(red: 0.44, green: 0.26, blue: 0.12, alpha: 0.98))
        g.fillEllipse(in: CGRect(x: 4, y: 2, width: 18, height: 11))
        g.setFillColor(CGColor(red: 0.34, green: 0.19, blue: 0.09, alpha: 0.92))
        g.fillEllipse(in: CGRect(x: 9, y: 11, width: 10, height: 8))
    }

    override func mouseDown(with event: NSEvent) {
        (window as? PoopWindow)?.dismiss()
    }
}
