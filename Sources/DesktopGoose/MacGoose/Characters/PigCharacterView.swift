// Procedurally drawn pig character.

import AppKit
import CoreGraphics

final class PigCharacterView: NSView {
    weak var goose: MacintoshGoose?

    private static let shadowPattern = CGColor(red: 0, green: 0, blue: 0, alpha: 0.12)

    override func draw(_ dirtyRect: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext,
              let goose else { return }

        g.saveGState()
        g.scaleBy(x: 1, y: -1)
        g.translateBy(x: CGFloat(100 - goose.position.x),
                      y: CGFloat(100 - goose.position.y) - bounds.height)

        goose.UpdateRig()

        let dir  = Vector2.GetFromAngleDegrees(goose.direction)
        let perp = Vector2.GetFromAngleDegrees(goose.direction + 90)
        let up   = Vector2(0, -1)

        let pigPink     = CGColor(red: 1.00, green: 0.70, blue: 0.76, alpha: 1)
        let pigPinkDark = CGColor(red: 0.82, green: 0.42, blue: 0.52, alpha: 1)
        let belly       = CGColor(red: 1.00, green: 0.82, blue: 0.86, alpha: 1)
        let snoutColor  = CGColor(red: 0.96, green: 0.58, blue: 0.68, alpha: 1)
        let dark        = CGColor(red: 0.15, green: 0.06, blue: 0.08, alpha: 1)

        let bodyCenter      = goose.gooseRig.bodyCenter
        let underbodyCenter = goose.gooseRig.underbodyCenter
        let neckBase        = goose.gooseRig.neckBase
        let neckHeadPoint   = goose.gooseRig.neckHeadPoint
        let head1EndPoint   = goose.gooseRig.head1EndPoint
        let head2EndPoint   = goose.gooseRig.head2EndPoint

        g.setLineCap(.round)

        // Shadow
        fillEllipse(g, color: Self.shadowPattern, center: goose.position, xR: 22, yR: 16)

        // Curly tail — control points in local (dir/up) space so they rotate
        // correctly with the character regardless of facing direction.
        let tailRoot = bodyCenter - dir * 16
        let ctrl1    = tailRoot - dir * 5 + up * 9
        let ctrl2    = tailRoot + dir * 3 + up * 12
        let tailTip  = tailRoot + dir * 4 + up * 7
        g.setStrokeColor(pigPinkDark)
        g.setLineWidth(3)
        g.move(to: cg(tailRoot))
        g.addCurve(to: cg(tailTip), control1: cg(ctrl1), control2: cg(ctrl2))
        g.strokePath()

        // Legs
        let footL = goose.lFootPos
        let footR = goose.rFootPos
        if goose.isResting {
            fillEllipse(g, color: pigPink, center: bodyCenter - dir * 13 - perp * 7, xR: 7, yR: 9)
            fillEllipse(g, color: pigPink, center: bodyCenter - dir * 13 + perp * 7, xR: 7, yR: 9)
            drawHoof(g, anchor: bodyCenter - dir * 4 - perp * 6, color: pigPinkDark)
            drawHoof(g, anchor: bodyCenter - dir * 4 + perp * 6, color: pigPinkDark)
        } else {
            drawPigLeg(g, foot: footL - dir * 22, up: up, color: pigPinkDark)
            drawPigLeg(g, foot: footR - dir * 22, up: up, color: pigPinkDark)
        }
        drawPigLeg(g, foot: footL + dir * 15, up: up, color: pigPinkDark)
        drawPigLeg(g, foot: footR + dir * 15, up: up, color: pigPinkDark)

        // Body — outline then fill, belly on top
        let outlinePad: Float = 2
        drawCapsule(g, from: bodyCenter + dir * 11, to: bodyCenter - dir * 16,
                    width: 24 + outlinePad, color: pigPinkDark)
        drawCapsule(g, from: bodyCenter + dir * 11, to: bodyCenter - dir * 16,
                    width: 24, color: pigPink)
        drawCapsule(g, from: underbodyCenter + dir * 9, to: underbodyCenter - dir * 13,
                    width: 16, color: belly)

        // Neck (stocky)
        drawCapsule(g, from: neckBase, to: neckHeadPoint, width: 16 + outlinePad, color: pigPinkDark)
        drawCapsule(g, from: neckBase, to: neckHeadPoint, width: 16, color: pigPink)

        // Head
        drawCapsule(g, from: neckHeadPoint, to: head1EndPoint, width: 18 + outlinePad, color: pigPinkDark)
        drawCapsule(g, from: head1EndPoint,  to: head2EndPoint, width: 14 + outlinePad, color: pigPinkDark)
        drawCapsule(g, from: neckHeadPoint, to: head1EndPoint, width: 18, color: pigPink)
        drawCapsule(g, from: head1EndPoint,  to: head2EndPoint, width: 14, color: pigPink)

        // Front legs (drawn over body front edge)
        // already drawn above in the shared drawPigLeg calls

        // Ears — upright pointed pig ears.
        // earTip spreads slightly outward (±perp) so they don't overlap the head.
        let earBaseL = neckHeadPoint - perp * 5 + up * 3
        let earBaseR = neckHeadPoint + perp * 5 + up * 3
        let earTipL  = earBaseL + up * 9 - perp * 1.5
        let earTipR  = earBaseR + up * 9 + perp * 1.5
        drawCapsule(g, from: earBaseL, to: earTipL, width: 7, color: pigPinkDark)
        drawCapsule(g, from: earBaseR, to: earTipR, width: 7, color: pigPinkDark)
        drawCapsule(g, from: earBaseL + up * 0.5, to: earTipL - up * 1.5, width: 3.5, color: pigPink)
        drawCapsule(g, from: earBaseR + up * 0.5, to: earTipR - up * 1.5, width: 3.5, color: pigPink)

        // Snout disc + nostrils.
        // Nostrils offset along perp → always face-on regardless of direction.
        let snoutCenter = head2EndPoint + dir * 3
        fillCircle(g, color: pigPinkDark, center: snoutCenter, radius: 6.5)
        fillCircle(g, color: snoutColor,  center: snoutCenter, radius: 5.5)
        fillCircle(g, color: dark, center: snoutCenter - perp * 2.2, radius: 1.4)
        fillCircle(g, color: dark, center: snoutCenter + perp * 2.2, radius: 1.4)

        // Eyes
        let eyeBase = neckHeadPoint + up * 2 + dir * 3.5
        fillCircle(g, color: dark, center: eyeBase - perp * 3, radius: 1.8)
        fillCircle(g, color: dark, center: eyeBase + perp * 3, radius: 1.8)

        // Speech bubble
        if let speech = goose.speechText, !speech.isEmpty {
            drawSpeechBubble(g, text: speech, anchor: neckHeadPoint, up: up, dogPos: goose.position)
        }

        g.restoreGState()
    }

    // MARK: - Pig-specific primitives

    private func drawHoof(_ g: CGContext, anchor: Vector2, color: CGColor) {
        fillEllipse(g, color: color, center: anchor, xR: 3.2, yR: 2.0)
    }

    private func drawPigLeg(_ g: CGContext, foot: Vector2, up: Vector2, color: CGColor) {
        drawCapsule(g, from: foot + up * 3, to: foot + up * 0.8, width: 4.5, color: color)
        drawHoof(g, anchor: foot + up * 0.5, color: color)
    }

    // MARK: - Drawing primitives (same as ChickCharacterView)

    private func cg(_ v: Vector2) -> CGPoint {
        CGPoint(x: CGFloat(v.x), y: CGFloat(v.y))
    }

    private func drawCapsule(_ g: CGContext, from: Vector2, to: Vector2, width: Float, color: CGColor) {
        g.setStrokeColor(color)
        g.setLineWidth(CGFloat(width))
        g.move(to: cg(from))
        g.addLine(to: cg(to))
        g.strokePath()
    }

    private func fillCircle(_ g: CGContext, color: CGColor, center: Vector2, radius: Float) {
        g.setFillColor(color)
        g.fillEllipse(in: CGRect(x: CGFloat(center.x - radius),
                                 y: CGFloat(center.y - radius),
                                 width: CGFloat(radius * 2),
                                 height: CGFloat(radius * 2)))
    }

    private func fillEllipse(_ g: CGContext, color: CGColor, center: Vector2, xR: Float, yR: Float) {
        g.setFillColor(color)
        g.fillEllipse(in: CGRect(x: CGFloat(center.x - xR),
                                 y: CGFloat(center.y - yR),
                                 width: CGFloat(xR * 2),
                                 height: CGFloat(yR * 2)))
    }

    private func drawSpeechBubble(_ g: CGContext, text: String, anchor: Vector2,
                                  up: Vector2, dogPos: Vector2) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.black
        ]
        let attrLines = text.components(separatedBy: "\n")
            .map { NSAttributedString(string: $0, attributes: attrs) }
        let lineSizes = attrLines.map { $0.size() }
        let textW = lineSizes.map { $0.width }.max() ?? 0
        let lineH = lineSizes.map { $0.height }.max() ?? 0
        let textH = lineH * CGFloat(attrLines.count)
        let padX: CGFloat = 9, padY: CGFloat = 6
        let w = textW + padX * 2
        let h = textH + padY * 2
        var cx = CGFloat(anchor.x + up.x * (Float(h) / 2 + 16))
        var cy = CGFloat(anchor.y + up.y * (Float(h) / 2 + 16))
        let half: CGFloat = 100
        let m: CGFloat = 3
        var vx = (cx - CGFloat(dogPos.x)) + half
        var vy = -(cy - CGFloat(dogPos.y)) + half
        vx = min(max(vx, w / 2 + m), bounds.width  - w / 2 - m)
        vy = min(max(vy, h / 2 + m), bounds.height - h / 2 - m)
        cx = CGFloat(dogPos.x) + (vx - half)
        cy = CGFloat(dogPos.y) - (vy - half)
        let center = Vector2(Float(cx), Float(cy))
        let rect = CGRect(x: CGFloat(center.x) - w / 2, y: CGFloat(center.y) - h / 2,
                          width: w, height: h)
        let fill = CGColor(red: 1, green: 1, blue: 1, alpha: 0.96)
        let edge = CGColor(red: 0.52, green: 0.22, blue: 0.30, alpha: 1)

        let bx = CGFloat(center.x)
        let by = CGFloat(center.y) + h / 2
        g.beginPath()
        g.move(to: CGPoint(x: bx - 6, y: by - 1))
        g.addLine(to: CGPoint(x: bx + 6, y: by - 1))
        g.addLine(to: CGPoint(x: bx, y: by + 8))
        g.closePath()
        g.setFillColor(fill)
        g.fillPath()

        let body = CGPath(roundedRect: rect, cornerWidth: 7, cornerHeight: 7, transform: nil)
        g.setFillColor(fill)
        g.addPath(body)
        g.fillPath()
        g.setStrokeColor(edge)
        g.setLineWidth(1.5)
        g.addPath(body)
        g.strokePath()

        g.saveGState()
        g.translateBy(x: CGFloat(center.x), y: CGFloat(center.y))
        g.scaleBy(x: 1, y: -1)
        let nsCtx = NSGraphicsContext(cgContext: g, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        for (i, line) in attrLines.enumerated() {
            let lw = lineSizes[i].width
            let y = textH / 2 - CGFloat(i + 1) * lineH
            line.draw(at: NSPoint(x: -lw / 2, y: y))
        }
        NSGraphicsContext.restoreGraphicsState()
        g.restoreGState()
    }
}
