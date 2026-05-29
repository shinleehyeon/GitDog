// Port of: MacGoose.Windows/MemeWindow.cs

import AppKit
import CoreGraphics

final class MemeWindow: GooseWindow {
    init(image: NSImage, url: URL) {
        super.init(width: 400, height: 400)
        self.representedURL = url
        self.title = url.lastPathComponent
        let iv = NSImageView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        iv.image = image
        self.contentView = iv
    }
}
