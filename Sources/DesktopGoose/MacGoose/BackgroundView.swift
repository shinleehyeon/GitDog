// Port of: MacGoose/BackgroundView.cs

import AppKit
import CoreGraphics

final class BackgroundView: NSView {
    weak var goose: MacintoshGoose?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let g = NSGraphicsContext.current?.cgContext else { return }
        g.saveGState()
        goose?.RenderFootmarks(g)
        g.restoreGState()
    }
}
