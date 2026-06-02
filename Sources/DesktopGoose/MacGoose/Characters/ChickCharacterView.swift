// Local addition — procedurally drawn dachshund-style character.
//
// Keep the goose engine rig/anchors identical so behavior stays stable
// (pathing, off-screen tasks, cursor grabbing offsets). We only restyle
// legs/face while preserving the goose-like silhouette and proportions.

import AppKit
import CoreGraphics

final class ChickCharacterView: NSView {
    weak var goose: MacintoshGoose?
    private static let gooseLikeShadowPattern: CGColor = {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let bmp = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
                                  bytesPerRow: 8, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            return NSColor.lightGray.cgColor
        }
        bmp.clear(CGRect(x: 0, y: 0, width: 2, height: 2))
        bmp.setFillColor(NSColor.lightGray.cgColor)
        bmp.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let cgImage = bmp.makeImage() else { return NSColor.lightGray.cgColor }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: 2, height: 2))
        return NSColor(patternImage: image).cgColor
    }()

    override func draw(_ dirtyRect: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext,
              let goose else { return }

        g.saveGState()
        // Same coord transform as MacintoshGoose.Render().
        g.scaleBy(x: 1, y: -1)
        g.translateBy(x: CGFloat(100 - goose.position.x),
                      y: CGFloat(100 - goose.position.y) - bounds.height)

        // Critical: keep rig data fresh every frame. Several AI behaviors use
        // gooseRig.head2EndPoint; stale rig data causes odd off-screen motion.
        goose.UpdateRig()

        let dir = Vector2.GetFromAngleDegrees(goose.direction)
        let perp = Vector2.GetFromAngleDegrees(goose.direction + 90)
        let up = Vector2(0, -1)

        // --- Palette ---
        let coat = CGColor(red: 0.57, green: 0.34, blue: 0.19, alpha: 1)
        let coatDark = CGColor(red: 0.32, green: 0.20, blue: 0.12, alpha: 1)
        let tan = CGColor(red: 0.80, green: 0.60, blue: 0.37, alpha: 1)
        let nose = CGColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)
        let bodyCenter = goose.gooseRig.bodyCenter
        let underbodyCenter = goose.gooseRig.underbodyCenter

        g.setLineCap(.round)

        // --- Shadow ---
        fillEllipse(g, color: Self.gooseLikeShadowPattern, center: goose.position, xR: 20, yR: 15)

        // --- Legs (4 legs look) ---
        // Back legs follow goose foot anchors (animated by solver).
        let footL = goose.lFootPos
        let footR = goose.rFootPos
        if goose.isResting {
            // Sitting: rear folds under into haunches with the rear paws tucked
            // forward; the front legs stay planted.
            fillEllipse(g, color: coat, center: bodyCenter - dir * 13 - perp * 7, xR: 7, yR: 9)
            fillEllipse(g, color: coat, center: bodyCenter - dir * 13 + perp * 7, xR: 7, yR: 9)
            drawDogPaw(g, anchor: bodyCenter - dir * 4 - perp * 6, color: coatDark)
            drawDogPaw(g, anchor: bodyCenter - dir * 4 + perp * 6, color: coatDark)
        } else {
            // Separate rear/front feet further for a clearer 4-leg silhouette.
            let rearLFoot = footL - dir * 22
            let rearRFoot = footR - dir * 22
            drawLeg(g, foot: rearLFoot, up: up, color: coatDark)
            drawLeg(g, foot: rearRFoot, up: up, color: coatDark)
        }
        // Front legs stay anchored from the original foot bases.
        // This keeps front-leg placement fixed even if rear-leg offset changes.
        let frontOffsetFromBase = dir * 15
        drawLeg(g, foot: footL + frontOffsetFromBase, up: up, color: coatDark)
        drawLeg(g, foot: footR + frontOffsetFromBase, up: up, color: coatDark)                  

        // --- Body + neck/head (goose silhouette kept intentionally close) ---
        let outlinePad: Float = 2
        let bodyFrontLength: Float = 11
        let bodyRearLength: Float = 16
        let underbodyFrontLength: Float = 9
        let underbodyRearLength: Float = 13
        drawCapsule(g, from: bodyCenter + dir * bodyFrontLength, to: bodyCenter - dir * bodyRearLength,
                    width: 22 + outlinePad, color: coatDark)
        drawCapsule(g, from: goose.gooseRig.neckBase, to: goose.gooseRig.neckHeadPoint,
                    width: 13 + outlinePad, color: coatDark)
        drawCapsule(g, from: goose.gooseRig.neckHeadPoint, to: goose.gooseRig.head1EndPoint,
                    width: 15 + outlinePad, color: coatDark)
        drawCapsule(g, from: goose.gooseRig.head1EndPoint, to: goose.gooseRig.head2EndPoint,
                    width: 10 + outlinePad, color: coatDark)
        drawCapsule(g, from: underbodyCenter + dir * underbodyFrontLength, to: underbodyCenter - dir * underbodyRearLength,
                    width: 15, color: tan)
        drawCapsule(g, from: bodyCenter + dir * bodyFrontLength, to: bodyCenter - dir * bodyRearLength,
                    width: 22, color: coat)
        drawCapsule(g, from: goose.gooseRig.neckBase, to: goose.gooseRig.neckHeadPoint,
                    width: 13, color: coat)
        drawCapsule(g, from: goose.gooseRig.neckHeadPoint, to: goose.gooseRig.head1EndPoint,
                    width: 15, color: coat)
        drawCapsule(g, from: goose.gooseRig.head1EndPoint, to: goose.gooseRig.head2EndPoint,
                    width: 10, color: coat)

        // --- Face (replace beak with snout) ---
        let snoutStart = goose.gooseRig.head2EndPoint
        let snoutEnd = snoutStart + dir * 6
        drawCapsule(g, from: snoutStart, to: snoutEnd, width: 8, color: tan)
        fillCircle(g, color: nose, center: snoutEnd + dir * 0.8, radius: 2.2)

        // --- Ears (simple floppy ears) ---
        let earBaseL = goose.gooseRig.neckHeadPoint - perp * 4 + up * 1
        let earBaseR = goose.gooseRig.neckHeadPoint + perp * 4 + up * 1
        drawCapsule(g, from: earBaseL, to: earBaseL + up * -5 + dir * -1.5, width: 4, color: coatDark)
        drawCapsule(g, from: earBaseR, to: earBaseR + up * -5 + dir * -1.5, width: 4, color: coatDark)

        // --- Eyes ---
        let eyeBase = goose.gooseRig.neckHeadPoint + up * 2 + dir * 3.8
        let eyeL = eyeBase - perp * 3
        let eyeR = eyeBase + perp * 3
        fillCircle(g, color: nose, center: eyeL, radius: 1.8)
        fillCircle(g, color: nose, center: eyeR, radius: 1.8)

        // --- Speech bubble (e.g. a "커밋해!" nudge) ---
        if let speech = goose.speechText, !speech.isEmpty {
            drawSpeechBubble(g, text: speech, anchor: goose.gooseRig.neckHeadPoint,
                             up: up, dogPos: goose.position)
        }

        g.restoreGState()
    }

    // Draw a small rounded speech bubble above the dog's head. The drawing
    // context is y-flipped (see draw()), so the text is rendered through a
    // local flip to keep it upright.
    private func drawSpeechBubble(_ g: CGContext, text: String, anchor: Vector2,
                                  up: Vector2, dogPos: Vector2) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.black
        ]
        // Pre-split on "\n" and lay the lines out by hand — draw(at:) renders
        // each single line upright reliably (see the local y-flip below).
        let attrLines = text.components(separatedBy: "\n")
            .map { NSAttributedString(string: $0, attributes: attrs) }
        let lineSizes = attrLines.map { $0.size() }
        let textW = lineSizes.map { $0.width }.max() ?? 0
        let lineH = lineSizes.map { $0.height }.max() ?? 0
        let textH = lineH * CGFloat(attrLines.count)
        let padX: CGFloat = 9, padY: CGFloat = 6
        let w = textW + padX * 2
        let h = textH + padY * 2
        // Desired center: above the head (up = (0,-1) in this coord space).
        var cx = CGFloat(anchor.x + up.x * (Float(h) / 2 + 16))
        var cy = CGFloat(anchor.y + up.y * (Float(h) / 2 + 16))
        // Keep the whole bubble inside the 200×200 character view so it never
        // clips when the dog walks to the top or an edge. Convert the center to
        // view space, clamp it, then convert back. (100 matches the fixed
        // transform offset / the view's half-size — see draw().)
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
        let edge = CGColor(red: 0.32, green: 0.20, blue: 0.12, alpha: 1)

        // Tail pointing down toward the head (down = +y here).
        let bx = CGFloat(center.x)
        let by = CGFloat(center.y) + h / 2
        g.beginPath()
        g.move(to: CGPoint(x: bx - 6, y: by - 1))
        g.addLine(to: CGPoint(x: bx + 6, y: by - 1))
        g.addLine(to: CGPoint(x: bx, y: by + 8))
        g.closePath()
        g.setFillColor(fill)
        g.fillPath()

        // Rounded bubble body.
        let body = CGPath(roundedRect: rect, cornerWidth: 7, cornerHeight: 7, transform: nil)
        g.setFillColor(fill)
        g.addPath(body)
        g.fillPath()
        g.setStrokeColor(edge)
        g.setLineWidth(1.5)
        g.addPath(body)
        g.strokePath()

        // Text — undo the y-flip so glyphs are upright, then stack the lines
        // top-to-bottom centered (y is up here, so line 0 sits highest).
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

    // MARK: - Drawing primitives (mirror MacintoshGoose's FillCircleFromCenter / DrawLine)

    private func cg(_ v: Vector2) -> CGPoint {
        CGPoint(x: CGFloat(v.x), y: CGFloat(v.y))
    }

    private func drawCapsule(_ g: CGContext, from: Vector2, to: Vector2,
                             width: Float, color: CGColor) {
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

    private func fillEllipse(_ g: CGContext, color: CGColor, center: Vector2,
                             xR: Float, yR: Float) {
        g.setFillColor(color)
        g.fillEllipse(in: CGRect(x: CGFloat(center.x - xR),
                                 y: CGFloat(center.y - yR),
                                 width: CGFloat(xR * 2),
                                 height: CGFloat(yR * 2)))
    }

    private func drawLeg(_ g: CGContext, foot: Vector2, up: Vector2, color: CGColor) {
        let legTop = foot + up * 3.0
        drawCapsule(g, from: legTop, to: foot + up * 0.8, width: 3.0, color: color)
        drawDogPaw(g, anchor: foot + up * 1.0, color: color)
    }

    private func drawDogPaw(_ g: CGContext, anchor: Vector2, color: CGColor) {
        // Keep footprint size close to previous paw, but shape it like a dog paw:
        // one rounded base pad + four toe beans.
        fillEllipse(g, color: color, center: anchor + Vector2(0, -0.55), xR: 2.6, yR: 1.55)  // base pad
        fillEllipse(g, color: color, center: anchor + Vector2(-2.0, 1.2), xR: 0.72, yR: 0.92) // toe 1
        fillEllipse(g, color: color, center: anchor + Vector2(-0.7, 1.8), xR: 0.72, yR: 0.96) // toe 2
        fillEllipse(g, color: color, center: anchor + Vector2(0.7, 1.8), xR: 0.72, yR: 0.96)  // toe 3
        fillEllipse(g, color: color, center: anchor + Vector2(2.0, 1.2), xR: 0.72, yR: 0.92)  // toe 4
    }
}
