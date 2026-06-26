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

        if let pos = goose?.clickIndicatorScreenPos {
            let elapsed = Time.time - (goose?.clickIndicatorStartTime ?? 0)
            if elapsed < 0.7 {
                drawCircleIndicator(g, at: pos, elapsed: elapsed)
            } else {
                goose?.clickIndicatorScreenPos = nil
            }
        }
    }

    private func drawCircleIndicator(_ g: CGContext, at pos: CGPoint, elapsed: Float) {
        let t      = CGFloat(elapsed / 0.7)
        let alpha  = 1.0 - t * t
        let radius = CGFloat(10 + t * 6)

        g.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha * 0.9))
        g.setLineWidth(2.5)
        g.strokeEllipse(in: CGRect(x: pos.x - radius, y: pos.y - radius,
                                   width: radius * 2, height: radius * 2))

        g.setStrokeColor(CGColor(red: 0.35, green: 0.35, blue: 0.35, alpha: alpha * 0.5))
        g.setLineWidth(1.0)
        g.strokeEllipse(in: CGRect(x: pos.x - radius - 1.5, y: pos.y - radius - 1.5,
                                   width: (radius + 1.5) * 2, height: (radius + 1.5) * 2))
    }
}
