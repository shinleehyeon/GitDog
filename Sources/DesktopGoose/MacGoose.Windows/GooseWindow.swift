// Port of: MacGoose.Windows/GooseWindow.cs

import AppKit
import CoreGraphics

class GooseWindow: NSWindow, Goose.IMovableForm {
    private(set) var CloseAction: (() -> Void)?

    var Width: Int { Int(frame.size.width) }
    var Height: Int { Int(frame.size.height) }

    init(width: Int, height: Int) {
        super.init(contentRect: CGRect(x: -1000, y: -1000, width: width, height: height),
                   styleMask: [.titled, .closable, .miniaturizable],
                   backing: .buffered,
                   defer: false)
        self.isReleasedWhenClosed = false
        self.orderOut(nil)
        self.isMovable = false
        self.collectionBehavior = [.canJoinAllSpaces]
        self.delegate = AppDelegate.SharedAppDelegate
    }

    func Show(_ closeAction: @escaping () -> Void) {
        level = .floating
        CloseAction = closeAction
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    func SetPosition(_ point: CGPoint) {
        let height = (screen ?? NSScreen.main!).frame.height
        let topLeft = CGPoint(x: point.x, y: height - point.y)
        setFrameTopLeftPoint(topLeft)
        self.orderFront(nil)
        MakeMovableSoon()
    }

    private func MakeMovableSoon() {
        NSObject.cancelPreviousPerformRequests(withTarget: self,
                                               selector: #selector(MakeMovable(_:)),
                                               object: self)
        perform(#selector(MakeMovable(_:)), with: self, afterDelay: 0.1)
    }

    @objc func MakeMovable(_ sender: Any?) {
        isMovable = true
        if !isMiniaturized {
            makeKeyAndOrderFront(sender)
        }
        level = .normal
    }
}
