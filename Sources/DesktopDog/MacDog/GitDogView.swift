// Port of: MacGoose/GooseView.cs

import AppKit
import CoreGraphics

final class GooseView: NSView {
    weak var goose: MacintoshGoose?

    override func draw(_ dirtyRect: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext else { return }
        g.saveGState()
        goose?.Render(g)
        g.restoreGState()
    }
}
