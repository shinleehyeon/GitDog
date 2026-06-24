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
            if elapsed < 0.65 {
                drawClickIndicator(g, at: pos, elapsed: elapsed)
            } else {
                goose?.clickIndicatorScreenPos = nil
            }
        }
    }

    private func drawClickIndicator(_ g: CGContext, at pos: CGPoint, elapsed: Float) {
        g.setLineCap(.round)

        // 3 expanding rings, staggered by 0.12s each
        for i in 0..<3 {
            let delay = Float(i) * 0.12
            let t = elapsed - delay
            guard t > 0 && t < 0.5 else { continue }
            let progress = CGFloat(t / 0.5)
            let radius = 5 + progress * 20
            let alpha = 1.0 - progress

            g.setStrokeColor(CGColor(red: 0.18, green: 0.90, blue: 0.85, alpha: alpha))
            g.setLineWidth(2.2)
            g.strokeEllipse(in: CGRect(x: pos.x - radius, y: pos.y - radius,
                                       width: radius * 2, height: radius * 2))
        }

        // Center cross — fades out in first 0.2s
        let crossAlpha = CGFloat(max(0, 1.0 - elapsed / 0.2))
        if crossAlpha > 0 {
            g.setStrokeColor(CGColor(red: 0.18, green: 0.90, blue: 0.85, alpha: crossAlpha))
            g.setLineWidth(2.0)
            let s: CGFloat = 7
            g.move(to: CGPoint(x: pos.x - s, y: pos.y))
            g.addLine(to: CGPoint(x: pos.x + s, y: pos.y))
            g.strokePath()
            g.move(to: CGPoint(x: pos.x, y: pos.y - s))
            g.addLine(to: CGPoint(x: pos.x, y: pos.y + s))
            g.strokePath()
        }
    }
}
