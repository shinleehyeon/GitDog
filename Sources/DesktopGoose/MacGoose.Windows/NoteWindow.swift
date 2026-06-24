// Port of: MacGoose.Windows/NoteWindow.cs

import AppKit
import CoreGraphics

private final class NoteContentView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let headerH: CGFloat = 28

        // Yellow header
        NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.0, alpha: 1).setFill()
        bounds.divided(atDistance: headerH, from: .minYEdge).slice.fill()

        // Off-white paper body
        NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.95, alpha: 1).setFill()
        bounds.divided(atDistance: headerH, from: .minYEdge).remainder.fill()

        // Perforated dots row at the header/body border
        let dotD: CGFloat = 4.5
        let gap: CGFloat = 9.5
        NSColor(calibratedWhite: 0.70, alpha: 1).setFill()
        var x: CGFloat = gap
        while x + dotD < bounds.width - gap {
            let rect = NSRect(x: x, y: headerH - dotD / 2, width: dotD, height: dotD)
            NSBezierPath(ovalIn: rect).fill()
            x += dotD + gap
        }

        // Ruled lines in the body
        NSColor(calibratedWhite: 0.82, alpha: 1).setStroke()
        let lineInset: CGFloat = 16
        let lineStartY: CGFloat = headerH + 38
        let lineSpacing: CGFloat = 22
        var lineY = lineStartY
        while lineY < bounds.height - 12 {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: lineInset, y: lineY))
            path.line(to: NSPoint(x: bounds.width - lineInset, y: lineY))
            path.lineWidth = 0.7
            path.stroke()
            lineY += lineSpacing
        }
    }
}

final class NoteWindow: GooseWindow {
    private var textView: NSTextView!

    init(title: String, text: String) {
        let w: CGFloat = 270
        let h: CGFloat = 210
        let headerH: CGFloat = 28
        super.init(width: Int(w), height: Int(h))
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.0, alpha: 1)

        let bg = NoteContentView(frame: CGRect(x: 0, y: 0, width: w, height: h))
        self.contentView = bg

        let hPad: CGFloat = 14
        let bodyTop: CGFloat = headerH + 10
        textView = NSTextView(frame: CGRect(
            x: hPad,
            y: bodyTop,
            width: w - hPad * 2,
            height: h - bodyTop - 10
        ))
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 2, height: 0)

        let font = NSFont(name: "HelveticaNeue", size: 14)
            ?? NSFont.systemFont(ofSize: 14)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.2, alpha: 1)
        ]
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: attrs)
        )

        bg.addSubview(textView)
    }
}
