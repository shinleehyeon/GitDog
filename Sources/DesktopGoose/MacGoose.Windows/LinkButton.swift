// Port of: MacGoose.Windows/LinkButton.cs

import AppKit
import CoreGraphics

final class LinkButton: NSView {
    let link: String

    init(_ rect: CGRect, _ link: String) {
        self.link = link
        super.init(frame: rect)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseUp(with event: NSEvent) {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }
}
