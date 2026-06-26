// Port of: MacGoose/MacintoshGoose.cs

import Foundation
import AppKit
import CoreGraphics

final class MacintoshGoose: Goose {
    private var tickTimer: Timer?
    private var shadowPattern: CGColor!
    private let memesDirectory: String
    private let notesDirectory: String
    private var settings: MacGooseSettings!
    private var gooseView: NSView!     // Either GooseView or ChickCharacterView, swappable.
    private var nextMemeImage: NSImage?
    private var nextMemeUrl: URL?
    private var nextMemeTitle: String?
    private var nextNoteText: String?
    private var nextNoteTitle: String?
    // Avoid fetching the same meme/note twice in a row.
    private var lastMemePath: String?
    private var lastNotePath: String?
    private var framerateObserver: NSObjectProtocol?
    private var behaviorObserver: NSObjectProtocol?
    private var rightClickMonitor: Any?

    var clickIndicatorScreenPos: CGPoint? = nil
    var clickIndicatorStartTime: Float = 0

    private(set) var Window: NSWindow!

    init(memesDirectory: String, notesDirectory: String) {
        self.memesDirectory = memesDirectory
        self.notesDirectory = notesDirectory
        super.init()

        let screenFrame = NSScreen.main?.frame ?? .zero
        let win = NSWindow(contentRect: screenFrame,
                           styleMask: [.borderless],
                           backing: .buffered,
                           defer: false)
        win.hasShadow = false
        win.alphaValue = 1
        win.backgroundColor = .clear
        win.isOpaque = false
        win.level = NSWindow.Level.screenSaver
        win.collectionBehavior = [.canJoinAllSpaces]
        win.ignoresMouseEvents = true
        win.orderFrontRegardless()
        self.Window = win

        let bg = BackgroundView()
        bg.goose = self
        bg.frame = win.frame
        bg.autoresizingMask = [.width, .height]
        win.contentView = bg

        installCharacterView(for: CharacterSettings.shared.current, into: bg)

        InitShadowPattern()
        settings = GooseConfig.settings as? MacGooseSettings

        framerateObserver = UserDefaults.standard.observe(forKey: MacGooseSettings.FrameRateKey) { [weak self] in
            self?.StartTimer()
        }
        behaviorObserver = NotificationCenter.default.addObserver(
            forName: .behaviorSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildBehaviorWeights()
        }
        StartTimer()
    }

    deinit {
        if let obs = framerateObserver {
            UserDefaults.standard.removeObserver(token: obs)
        }
    }

    private func StartTimer() {
        if tickTimer != nil {
            print("Changing framerate to \(settings.FrameRate)")
            tickTimer?.invalidate()
        }
        inverseFrameRate = 1.0 / settings.FrameRate
        tickTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(inverseFrameRate),
                                         repeats: true) { [weak self] _ in
            guard let self else { return }
            Time.TickTime()
            self.Tick()
            FriendDogManager.shared.tickAll()
            self.gooseView.frame = self.CalculateGooseViewFrame()
            if self.hasFootmarks || self.clickIndicatorScreenPos != nil {
                self.Window.contentView?.setNeedsDisplay(self.Window.contentView?.frame ?? .zero)
            }
            self.gooseView.setNeedsDisplay(self.gooseView.bounds)
        }
        if let t = tickTimer {
            RunLoop.main.add(t, forMode: .common)
            RunLoop.main.add(t, forMode: .eventTracking)
        }
    }

    private func installCharacterView(for kind: CharacterKind, into parent: NSView) {
        gooseView?.removeFromSuperview()
        let view: NSView
        switch kind {
        case .chick:
            let v = ChickCharacterView()
            v.goose = self
            view = v
        }
        view.frame = .zero
        parent.addSubview(view)
        gooseView = view
    }

    func swapCharacter(to kind: CharacterKind) {
        guard let bg = Window.contentView else { return }
        installCharacterView(for: kind, into: bg)
    }

    var coatVariant: Int = 0 {
        didSet { (gooseView as? ChickCharacterView)?.coatVariant = coatVariant }
    }

    func dismiss() {
        tickTimer?.invalidate()
        tickTimer = nil
        Window.orderOut(nil)
    }

    func makeExternallyManaged() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    func tickAndRedraw() {
        Tick()
        gooseView.frame = CalculateGooseViewFrame()
        gooseView.setNeedsDisplay(gooseView.bounds)
    }

    private func CalculateGooseViewFrame() -> CGRect {
        let h = Window.contentView?.frame.height ?? 0
        return CGRect(x: CGFloat(position.x) - 100,
                      y: h - CGFloat(position.y) - 100,
                      width: 200, height: 200)
    }

    private func InitShadowPattern() {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bmp = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
                            bytesPerRow: 8, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        bmp.clear(CGRect(x: 0, y: 0, width: 2, height: 2))
        bmp.setFillColor(NSColor.lightGray.cgColor)
        bmp.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let cgImage = bmp.makeImage()!
        let image = NSImage(cgImage: cgImage, size: NSSize(width: 2, height: 2))
        shadowPattern = NSColor(patternImage: image).cgColor
    }

    func RenderFootmarks(_ g: CGContext) {
        g.scaleBy(x: 1, y: -1)
        g.translateBy(x: 0, y: -(Window.contentView?.frame.height ?? 0))
        var flag = false
        let timeNow = Time.time
        let heartFootmarkColor = CGColor(red: 0.92, green: 0.18, blue: 0.30, alpha: 1)
        for i in 0..<footMarks.count {
            let markTime = footMarks[i].time
            let markLifetime = footMarks[i].lifetime
            let fadeStart = markTime + markLifetime
            let fadeEnd = fadeStart + FootMark.ShrinkTime
            if markTime <= timeNow && timeNow <= fadeEnd {
                let fadeProgress = SamMath.Clamp((timeNow - fadeStart) / FootMark.ShrinkTime, 0, 1)
                let radius = SamMath.Lerp(3, 0, fadeProgress)
                let defaultFootmarkColor = shadowPattern ?? NSColor.lightGray.cgColor
                let markColor = footMarks[i].isHeartTrail ? heartFootmarkColor : defaultFootmarkColor
                FillCircleFromCenter(g, markColor, footMarks[i].position, Int(radius))
                flag = true
            }
        }
        hasFootmarks = flag
    }

    override func Render(_ param: Any) {
        let g = param as! CGContext
        g.scaleBy(x: 1, y: -1)
        g.translateBy(x: CGFloat(100 - position.x),
                      y: CGFloat(100 - position.y) - gooseView.frame.height)
        UpdateRig()
        let vector = Vector2(position.x, position.y)
        let vector2 = Vector2(1.3, 0.4)
        let fromAngleDegrees = Vector2.GetFromAngleDegrees(direction)
        let fromAngleDegrees2 = Vector2.GetFromAngleDegrees(direction + 90)
        let vector3 = Vector2(0, -1)
        let num: Float = 2
        g.setFillColor(settings.GooseWhite)
        g.setLineCap(.round)
        FillCircleFromCenter(g, settings.GooseOrange, lFootPos, 4)
        FillCircleFromCenter(g, settings.GooseOrange, rFootPos, 4)
        FillEllipseFromCenter(g, shadowPattern, Int(vector.x), Int(vector.y), 20, 15)
        g.setStrokeColor(settings.GooseOutline)
        DrawLine(g, 22 + num, ToIntPoint(gooseRig.bodyCenter + fromAngleDegrees * 11),
                              ToIntPoint(gooseRig.bodyCenter - fromAngleDegrees * 11))
        DrawLine(g, 13 + num, ToIntPoint(gooseRig.neckBase), ToIntPoint(gooseRig.neckHeadPoint))
        DrawLine(g, 15 + num, ToIntPoint(gooseRig.neckHeadPoint), ToIntPoint(gooseRig.head1EndPoint))
        DrawLine(g, 10 + num, ToIntPoint(gooseRig.head1EndPoint), ToIntPoint(gooseRig.head2EndPoint))
        g.setStrokeColor(settings.GooseOutline)
        DrawLine(g, 15, ToIntPoint(gooseRig.underbodyCenter + fromAngleDegrees * 7),
                        ToIntPoint(gooseRig.underbodyCenter - fromAngleDegrees * 7))
        g.setStrokeColor(settings.GooseWhite)
        DrawLine(g, 22, ToIntPoint(gooseRig.bodyCenter + fromAngleDegrees * 11),
                        ToIntPoint(gooseRig.bodyCenter - fromAngleDegrees * 11))
        DrawLine(g, 13, ToIntPoint(gooseRig.neckBase), ToIntPoint(gooseRig.neckHeadPoint))
        DrawLine(g, 15, ToIntPoint(gooseRig.neckHeadPoint), ToIntPoint(gooseRig.head1EndPoint))
        DrawLine(g, 10, ToIntPoint(gooseRig.head1EndPoint), ToIntPoint(gooseRig.head2EndPoint))
        g.setStrokeColor(settings.GooseOrange)
        let vector4 = gooseRig.head2EndPoint + fromAngleDegrees * 5
        DrawLine(g, 9, ToIntPoint(gooseRig.head2EndPoint), ToIntPoint(vector4))
        let baseEye = gooseRig.neckHeadPoint + vector3 * 3 + fromAngleDegrees * 5
        let sideL = -fromAngleDegrees2 * vector2 * 5
        let sideR =  fromAngleDegrees2 * vector2 * 5
        let pos  = baseEye + sideL
        let pos2 = baseEye + sideR
        FillCircleFromCenter(g, settings.GooseEye, pos, 2)
        FillCircleFromCenter(g, settings.GooseEye, pos2, 2)
    }

    private func DrawLine(_ g: CGContext, _ penWidth: Float, _ from: CGPoint, _ to: CGPoint) {
        g.setLineWidth(CGFloat(penWidth))
        g.move(to: from)
        g.addLine(to: to)
        g.strokePath()
    }

    func FillCircleFromCenter(_ g: CGContext, _ color: CGColor, _ pos: Vector2, _ radius: Int) {
        FillEllipseFromCenter(g, color, Int(pos.x), Int(pos.y), radius, radius)
    }

    func FillCircleFromCenter(_ g: CGContext, _ color: CGColor, _ x: Int, _ y: Int, _ radius: Int) {
        FillEllipseFromCenter(g, color, x, y, radius, radius)
    }

    func FillEllipseFromCenter(_ g: CGContext, _ color: CGColor, _ x: Int, _ y: Int, _ xRadius: Int, _ yRadius: Int) {
        FillEllipseFromCenter(g, color, Vector2(Float(x), Float(y)),
                              Vector2(Float(xRadius), Float(yRadius)))
    }

    func FillEllipseFromCenter(_ g: CGContext, _ color: CGColor, _ position: Vector2, _ xyRadius: Vector2) {
        g.saveGState()
        g.setFillColor(color)
        g.fillEllipse(in: CGRect(x: CGFloat(position.x - xyRadius.x),
                                 y: CGFloat(position.y - xyRadius.y),
                                 width: CGFloat(xyRadius.x * 2),
                                 height: CGFloat(xyRadius.y * 2)))
        g.restoreGState()
    }

    override func BringWindowToForeground() {}

    override func CreateDonateForm() -> IMovableForm {
        // Donation feature disabled; return a benign placeholder window.
        return NoteWindow(title: "Donation Disabled", text: "This feature is turned off.")
    }

    func ShowNextMeme(_ image: NSImage?, _ url: URL?, _ title: String?) {
        nextMemeImage = image
        nextMemeUrl = url
        nextMemeTitle = title
        SetTask(.CollectWindow_Meme, honck: false)
    }

    func ShowNote(_ text: String, _ title: String?) {
        nextNoteText = text
        nextNoteTitle = title
        SetTask(.CollectWindow_Notepad, honck: false)
    }

    // Pick a random entry from `pool`, but skip `last` so the dog never
    // fetches the same thing twice in a row (unless there's only one choice).
    private func pickAvoidingRepeat(_ pool: [String], last: String?) -> String {
        guard pool.count > 1 else { return pool.first ?? "" }
        let candidates = pool.filter { $0 != last }
        let source = candidates.isEmpty ? pool : candidates
        return source[Int.random(in: 0..<source.count)]
    }

    override func CreateImageForm() -> IMovableForm {
        var image = nextMemeImage
        var url = nextMemeUrl
        if url == nil {
            let fm = FileManager.default
            let files = ((try? fm.contentsOfDirectory(atPath: memesDirectory)) ?? [])
                .filter { !$0.hasPrefix(".") }
                .map { (memesDirectory as NSString).appendingPathComponent($0) }
            let pool: [String] = files.isEmpty ? Goose.ImageUrls : files
            let text = pickAvoidingRepeat(pool, last: lastMemePath)
            lastMemePath = text
            url = text.hasPrefix("https://") ? URL(string: text) : URL(fileURLWithPath: text)
            if let u = url {
                if let img = NSImage(contentsOf: u) {
                    image = img
                } else {
                    image = NSImage(named: "Memes/Meme7.png")
                }
            }
        }
        let memeWindow = MemeWindow(image: image ?? NSImage(), url: url ?? URL(fileURLWithPath: "/"))
        if let title = nextMemeTitle {
            memeWindow.title = title
            nextMemeTitle = nil
        }
        nextMemeImage = nil
        nextMemeUrl = nil
        return memeWindow
    }

    override func GetNextNote() -> String {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(atPath: notesDirectory)) ?? [])
            .filter { $0.hasSuffix(".txt") }
            .map { (notesDirectory as NSString).appendingPathComponent($0) }
        if files.isEmpty {
            return super.GetNextNote()
        }
        let path = pickAvoidingRepeat(files, last: lastNotePath)
        lastNotePath = path
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? super.GetNextNote()
    }

    override func CreateTextForm(_ title: String, _ note: String) -> IMovableForm {
        let result = NoteWindow(title: nextNoteTitle ?? title, text: nextNoteText ?? note)
        nextNoteTitle = nil
        nextNoteText = nil
        return result
    }

    override func GetCursorPosition() -> Vector2 {
        let p = NSEvent.mouseLocation
        let h = NSScreen.main?.frame.height ?? 0
        return Vector2(Float(p.x), Float(h - p.y))
    }

    override func GetMainWindowHeight() -> Float {
        return Float(Window.frame.size.height)
    }

    override func GetMainWindowWidth() -> Float {
        return Float(Window.frame.size.width)
    }

    override func IsLeftMouseDown() -> Bool {
        return (NSEvent.pressedMouseButtons & 1) == 1
    }

    override func PlaySound(_ effect: SoundEffect) {
        // Sound feature disabled.
    }

    override func SetCursorClip(_ rect: CGRect) {
        if !rect.isEmpty {
            CGDisplayMoveCursorToPoint(CGMainDisplayID(),
                                       CGPoint(x: rect.minX, y: rect.minY))
        }
    }
}

/// UserDefaults KVO helper — Swift doesn't expose `addObserver(forKeyPath:)`
/// as a cleanly closure-based API for KVO on UserDefaults, so we use
/// NotificationCenter on `UserDefaults.didChangeNotification`.
extension UserDefaults {
    @discardableResult
    func observe(forKey key: String, _ block: @escaping () -> Void) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: self, queue: .main) { _ in
            block()
        }
    }

    func removeObserver(token: NSObjectProtocol) {
        NotificationCenter.default.removeObserver(token)
    }
}
