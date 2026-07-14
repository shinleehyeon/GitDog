// Local addition — procedurally drawn dachshund-style character.
//
// Keep the goose engine rig/anchors identical so behavior stays stable
// (pathing, off-screen tasks, cursor grabbing offsets). We only restyle
// legs/face while preserving the goose-like silhouette and proportions.

import AppKit
import CoreGraphics

final class ChickCharacterView: NSView {
    weak var dog: MacintoshGitDog?

    // 0 = original brown, 1 = reddish auburn, 2 = golden honey
    var coatVariant: Int = 0

    private static let palettes: [(coat: CGColor, dark: CGColor, tan: CGColor)] = [
        (CGColor(red: 0.57, green: 0.34, blue: 0.19, alpha: 1),
         CGColor(red: 0.32, green: 0.20, blue: 0.12, alpha: 1),
         CGColor(red: 0.80, green: 0.60, blue: 0.37, alpha: 1)),
        (CGColor(red: 0.68, green: 0.24, blue: 0.11, alpha: 1),
         CGColor(red: 0.38, green: 0.12, blue: 0.06, alpha: 1),
         CGColor(red: 0.87, green: 0.62, blue: 0.37, alpha: 1)),
        (CGColor(red: 0.76, green: 0.58, blue: 0.16, alpha: 1),
         CGColor(red: 0.44, green: 0.32, blue: 0.08, alpha: 1),
         CGColor(red: 0.94, green: 0.82, blue: 0.50, alpha: 1)),
    ]
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
              let dog else { return }

        g.saveGState()
        // Same coord transform as MacintoshGitDog.Render() — 100/200 are the
        // fixed base canvas size (pre-scale); don't swap in `bounds.height`
        // here since it now reflects the scaled view size, not the base 200.
        g.scaleBy(x: 1, y: -1)
        g.scaleBy(x: CGFloat(dog.sizeScale), y: CGFloat(dog.sizeScale))
        g.translateBy(x: CGFloat(100 - dog.position.x), y: CGFloat(100 - dog.position.y) - 200)

        // Critical: keep rig data fresh every frame. Several AI behaviors use
        // dogRig.head2EndPoint; stale rig data causes odd off-screen motion.
        dog.UpdateRig()

        let dir = Vector2.GetFromAngleDegrees(dog.direction)
        let perp = Vector2.GetFromAngleDegrees(dog.direction + 90)
        let up = Vector2(0, -1)

        // --- Palette ---
        let pal = Self.palettes[coatVariant % Self.palettes.count]
        let coat = pal.coat
        let coatDark = pal.dark
        let tan = pal.tan
        let nose = CGColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)
        let bodyCenter = dog.dogRig.bodyCenter
        let underbodyCenter = dog.dogRig.underbodyCenter

        g.setLineCap(.round)

        // --- Legs (4 legs look) ---
        // Back legs follow goose foot anchors (animated by solver).
        let footL = dog.lFootPos
        let footR = dog.rFootPos
        if dog.isResting {
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
        drawCapsule(g, from: dog.dogRig.neckBase, to: dog.dogRig.neckHeadPoint,
                    width: 13 + outlinePad, color: coatDark)
        drawCapsule(g, from: dog.dogRig.neckHeadPoint, to: dog.dogRig.head1EndPoint,
                    width: 15 + outlinePad, color: coatDark)
        drawCapsule(g, from: dog.dogRig.head1EndPoint, to: dog.dogRig.head2EndPoint,
                    width: 10 + outlinePad, color: coatDark)
        drawCapsule(g, from: underbodyCenter + dir * underbodyFrontLength, to: underbodyCenter - dir * underbodyRearLength,
                    width: 15, color: tan)
        drawCapsule(g, from: bodyCenter + dir * bodyFrontLength, to: bodyCenter - dir * bodyRearLength,
                    width: 22, color: coat)
        drawCapsule(g, from: dog.dogRig.neckBase, to: dog.dogRig.neckHeadPoint,
                    width: 13, color: coat)
        drawCapsule(g, from: dog.dogRig.neckHeadPoint, to: dog.dogRig.head1EndPoint,
                    width: 15, color: coat)
        drawCapsule(g, from: dog.dogRig.head1EndPoint, to: dog.dogRig.head2EndPoint,
                    width: 10, color: coat)

        // --- Face (replace beak with snout) ---
        let snoutStart = dog.dogRig.head2EndPoint
        let snoutEnd = snoutStart + dir * 6
        drawCapsule(g, from: snoutStart, to: snoutEnd, width: 8, color: tan)
        fillCircle(g, color: nose, center: snoutEnd + dir * 0.8, radius: 2.2)

        // --- Ears (simple floppy ears) ---
        let earBaseL = dog.dogRig.neckHeadPoint - perp * 4 + up * 1
        let earBaseR = dog.dogRig.neckHeadPoint + perp * 4 + up * 1
        drawCapsule(g, from: earBaseL, to: earBaseL + up * -5 + dir * -1.5, width: 4, color: coatDark)
        drawCapsule(g, from: earBaseR, to: earBaseR + up * -5 + dir * -1.5, width: 4, color: coatDark)

        // --- Eyes ---
        let eyeBase = dog.dogRig.neckHeadPoint + up * 2 + dir * 3.8
        let eyeL = eyeBase - perp * 3
        let eyeR = eyeBase + perp * 3
        fillCircle(g, color: nose, center: eyeL, radius: 1.8)
        fillCircle(g, color: nose, center: eyeR, radius: 1.8)

        // --- Speech bubble (e.g. a "커밋해!" nudge) ---
        if let speech = dog.speechText, !speech.isEmpty {
            drawSpeechBubble(g, text: speech, anchor: dog.dogRig.neckHeadPoint,
                             up: up, dogPos: dog.position, scale: dog.sizeScale)
        }

        g.restoreGState()
    }

    // Draw a small rounded speech bubble above the dog's head. The drawing
    // context is y-flipped (see draw()), so the text is rendered through a
    // local flip to keep it upright.
    private func drawSpeechBubble(_ g: CGContext, text: String, anchor: Vector2,
                                  up: Vector2, dogPos: Vector2, scale sizeScale: Float) {
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
        // Keep the whole bubble inside the character view so it never clips
        // when the dog walks to the top or an edge. Convert the center to view
        // space, clamp it, then convert back. (100 is the fixed base-canvas
        // half-size — see draw() — scaled by sizeScale since the view itself
        // is now sizeScale*200, and the bubble's own on-screen footprint
        // (w/h) is scaled by the same draw()-applied CTM scale too.)
        let scale = CGFloat(sizeScale)
        let half: CGFloat = 100 * scale
        let m: CGFloat = 3
        var vx = ((cx - CGFloat(dogPos.x)) * scale) + half
        var vy = (-(cy - CGFloat(dogPos.y)) * scale) + half
        vx = min(max(vx, (w / 2) * scale + m), bounds.width  - (w / 2) * scale - m)
        vy = min(max(vy, (h / 2) * scale + m), bounds.height - (h / 2) * scale - m)
        cx = CGFloat(dogPos.x) + (vx - half) / scale
        cy = CGFloat(dogPos.y) - (vy - half) / scale
        let center = Vector2(Float(cx), Float(cy))
        let rect = CGRect(x: CGFloat(center.x) - w / 2, y: CGFloat(center.y) - h / 2,
                          width: w, height: h)
        // Soft, cool-tinted chat-bubble look — a gentle drop shadow instead of
        // a hard outline, and a small rounded tail dot rather than a sharp
        // triangle.
        let fill = CGColor(red: 0.94, green: 0.97, blue: 0.99, alpha: 0.98)
        let shadow = CGColor(red: 0, green: 0, blue: 0, alpha: 0.22)

        g.saveGState()
        g.setShadow(offset: CGSize(width: 0, height: 2), blur: 5, color: shadow)

        // Small rounded tail dot pointing down toward the head.
        let bx = CGFloat(center.x)
        let by = CGFloat(center.y) + h / 2
        g.setFillColor(fill)
        g.fillEllipse(in: CGRect(x: bx - 3, y: by + 2, width: 6, height: 6))

        // Rounded bubble body.
        let cornerRadius = min(14, h / 2)
        let body = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        g.addPath(body)
        g.fillPath()
        g.restoreGState()

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

    // MARK: - Drawing primitives (mirror MacintoshGitDog's FillCircleFromCenter / DrawLine)

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
        g.setFillColor(color)
        let cx = CGFloat(anchor.x)
        let cy = CGFloat(anchor.y)
        let s: CGFloat = 5.0
        let r: CGFloat = 1.8
        // Rounded triangle: wide at top, pointed at bottom
        let tL  = CGPoint(x: cx - s,       y: cy - s * 0.3)
        let tR  = CGPoint(x: cx + s,       y: cy - s * 0.3)
        let bot = CGPoint(x: cx,           y: cy + s * 0.9)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: (tL.x + tR.x) / 2, y: tL.y))
        path.addArc(tangent1End: tR,  tangent2End: bot, radius: r)
        path.addArc(tangent1End: bot, tangent2End: tL,  radius: r)
        path.addArc(tangent1End: tL,  tangent2End: tR,  radius: r)
        path.closeSubpath()
        g.addPath(path)
        g.fillPath()
    }
}
