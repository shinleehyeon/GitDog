// Port of: MacGoose.Windows/NoteWindow.cs

import AppKit
import CoreGraphics

final class NoteWindow: GooseWindow {
    private var textView: NSTextView!

    init(title: String, text: String) {
        super.init(width: 250, height: 150)
        self.title = title
        textView = NSTextView(frame: CGRect(x: 0, y: 0,
                                            width: frame.width,
                                            height: frame.height))
        self.contentView = textView
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Menlo-Regular", size: NSFont.systemFontSize) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.controlTextColor
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attrs))
        textView.isEditable = false
    }
}
