// Port of: MacDog/MacintoshGitDog.cs

import Foundation
import AppKit
import CoreGraphics

final class MacintoshGitDog: GitDog {
    private var tickTimer: Timer?
    private let memesDirectory: String
    private let notesDirectory: String
    private var settings: MacDogSettings!
    private var dogView: NSView!     // Either GitDogView or ChickCharacterView, swappable.
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
    private var appearanceObserver: NSObjectProtocol?
    private var rightClickMonitor: Any?

    var clickIndicatorScreenPos: CGPoint? = nil
    var clickIndicatorStartTime: Float = 0
    private var lastDogViewFrame: CGRect = .zero
    // Previous-frame shrinking footmark/click dirty rects so faded marks get
    // erased without invalidating the entire fullscreen overlay.
    private var lastOverlayDirtyRects: [CGRect] = []
    private var lastCursorClipPoint: CGPoint = .zero
    private var spaceChangeObserver: NSObjectProtocol?

    // While asleep/screen-locked/display-off, the tick timer keeps firing
    // (only real system sleep suspends the process) — without this, Time.time
    // keeps advancing in the background, so timers like the 5-minute NabMouse
    // interval silently burn through while nobody's looking and can fire the
    // moment you're back. Freeze Time.TickTime()/Tick() entirely instead.
    private var isAsleep = false
    private var sleepObservers: [NSObjectProtocol] = []

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
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        win.ignoresMouseEvents = true
        win.orderFrontRegardless()
        self.Window = win

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.Window.orderFrontRegardless()
        }

        let bg = BackgroundView()
        bg.dog = self
        bg.frame = win.frame
        bg.autoresizingMask = [.width, .height]
        win.contentView = bg

        installCharacterView(for: CharacterSettings.shared.current, into: bg)

        settings = GitDogConfig.settings as? MacDogSettings
        sizeScale = Float(AppearanceSettings.shared.sizeScale)

        framerateObserver = UserDefaults.standard.observe(forKey: MacDogSettings.FrameRateKey) { [weak self] in
            self?.StartTimer()
        }
        behaviorObserver = NotificationCenter.default.addObserver(
            forName: .behaviorSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildBehaviorWeights()
        }
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .appearanceSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.sizeScale = Float(AppearanceSettings.shared.sizeScale)
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            sleepObservers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.isAsleep = true
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            sleepObservers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.isAsleep = false
            })
        }
        StartTimer()
    }

    deinit {
        if let obs = framerateObserver {
            UserDefaults.standard.removeObserver(token: obs)
        }
        if let obs = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        if let obs = behaviorObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = appearanceObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        let ws = NSWorkspace.shared.notificationCenter
        for obs in sleepObservers {
            ws.removeObserver(obs)
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
            guard let self, !self.isAsleep else { return }
            Time.TickTime()
            self.Tick()
            self.updateClickThrough()
            self.updatePathDrawing()
            FriendDogManager.shared.tickAll()
            let newFrame = self.CalculateGitDogViewFrame()
            self.invalidateOverlay(dogFrame: newFrame)
            self.lastDogViewFrame = newFrame
            self.dogView.frame = newFrame
            self.dogView.setNeedsDisplay(self.dogView.bounds)
        }
        if let t = tickTimer {
            RunLoop.main.add(t, forMode: .common)
            RunLoop.main.add(t, forMode: .eventTracking)
        }
    }

    // The overlay window spans the whole screen with ignoresMouseEvents=true
    // so clicks pass straight through to whatever's underneath (Finder,
    // browser text, etc.) everywhere except the dog. Without this, dragging
    // the dog also click-drags/selects whatever's behind it, since the click
    // falls straight through our window. Toggle it off only while the cursor
    // is actually over the dog (or mid-drag), so our window intercepts that
    // click instead of passing it through — same 30pt radius Tick() uses to
    // detect "over the dog" for grab/rest.
    private func updateClickThrough() {
        let cursor = GetCursorPosition()
        // Same scaled hit-test radius as Tick()'s overDog check.
        let overDog = Vector2.Distance(position + Vector2(0, 16) * sizeScale, cursor) < 42 * sizeScale
        let shouldIgnore = !(overDog || isGrabbed)
        // Only touch the window property when it actually changes — flipping
        // ignoresMouseEvents every frame during grab/throw is expensive.
        if Window.ignoresMouseEvents != shouldIgnore {
            Window.ignoresMouseEvents = shouldIgnore
        }
    }

    // Invalidate only what actually changed. Footmarks are static for most of
    // their lifetime — only appearance, shrink, and expiry need redraws. The
    // old path invalidated the entire fullscreen transparent window every frame
    // whenever any footprint was alive (~8s), which made grab/throw/nab crawl
    // after the dog had been wandering for a while.
    private func invalidateOverlay(dogFrame: CGRect) {
        let content = Window.contentView
        // Dog trail: clear where it was, paint where it is.
        content?.setNeedsDisplay(lastDogViewFrame.union(dogFrame))

        // Erase last frame's shrinking/click pixels (covers marks that just expired).
        for r in lastOverlayDirtyRects {
            content?.setNeedsDisplay(r)
        }

        let h = content?.frame.height ?? 0
        let timeNow = Time.time
        let pad = CGFloat(6 * sizeScale)
        let appearWindow = max(inverseFrameRate * 2, 0.034)
        var current: [CGRect] = []
        var anyAlive = false
        current.reserveCapacity(8)

        for mark in footMarks {
            let fadeStart = mark.time + mark.lifetime
            let fadeEnd = fadeStart + FootMark.ShrinkTime
            guard mark.time <= timeNow && timeNow <= fadeEnd else { continue }
            anyAlive = true
            let becomingVisible = (timeNow - mark.time) <= appearWindow
            let shrinking = timeNow >= fadeStart
            // Stable marks stay put; the dog-trail dirty rect restores them
            // whenever the dog walks over/off them. Only animate appearance/shrink.
            guard becomingVisible || shrinking else { continue }
            let r = CGRect(x: CGFloat(mark.position.x) - pad,
                           y: h - CGFloat(mark.position.y) - pad,
                           width: pad * 2, height: pad * 2)
            content?.setNeedsDisplay(r)
            current.append(r)
        }

        if let pos = clickIndicatorScreenPos {
            let r = CGRect(x: pos.x - 24, y: pos.y - 24, width: 48, height: 48)
            content?.setNeedsDisplay(r)
            current.append(r)
        }

        lastOverlayDirtyRects = current
        hasFootmarks = anyAlive
    }

    // Hold ⌥ (Option) and drag anywhere on screen to trace a path — the dog
    // walks it leg by leg once you release. Sampled every ~18pt of cursor
    // movement so the path isn't absurdly dense; polls the same global
    // mouse/modifier state IsLeftMouseDown()/GetCursorPosition() already use,
    // so it works regardless of ignoresMouseEvents/window focus.
    private var isDrawingPath = false
    private var drawnPath: [Vector2] = []
    private static let pathSampleDistance: Float = 18

    private func updatePathDrawing() {
        let drawing = NSEvent.modifierFlags.contains(.option) && IsLeftMouseDown()
        let cursor = GetCursorPosition()

        if drawing && !isDrawingPath {
            isDrawingPath = true
            drawnPath = [cursor]
        } else if drawing && isDrawingPath {
            if let last = drawnPath.last, Vector2.Distance(last, cursor) > Self.pathSampleDistance {
                drawnPath.append(cursor)
            }
        } else if !drawing && isDrawingPath {
            isDrawingPath = false
            if drawnPath.count > 1 {
                followPath(drawnPath)
            }
            drawnPath = []
        }
    }

    private func installCharacterView(for kind: CharacterKind, into parent: NSView) {
        dogView?.removeFromSuperview()
        let view: NSView
        switch kind {
        case .chick:
            let v = ChickCharacterView()
            v.dog = self
            view = v
        }
        view.frame = .zero
        parent.addSubview(view)
        dogView = view
    }

func swapCharacter(to kind: CharacterKind) {
        guard let bg = Window.contentView else { return }
        installCharacterView(for: kind, into: bg)
    }

    var coatVariant: Int = 0 {
        didSet { (dogView as? ChickCharacterView)?.coatVariant = coatVariant }
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
        let newFrame = CalculateGitDogViewFrame()
        invalidateOverlay(dogFrame: newFrame)
        lastDogViewFrame = newFrame
        dogView.frame = newFrame
        dogView.setNeedsDisplay(dogView.bounds)
    }

    private func CalculateGitDogViewFrame() -> CGRect {
        let h = Window.contentView?.frame.height ?? 0
        let half = 100 * CGFloat(sizeScale)
        return CGRect(x: CGFloat(position.x) - half,
                      y: h - CGFloat(position.y) - half,
                      width: half * 2, height: half * 2)
    }

    func RenderFootmarks(_ g: CGContext) {
        g.scaleBy(x: 1, y: -1)
        g.translateBy(x: 0, y: -(Window.contentView?.frame.height ?? 0))
        let timeNow = Time.time
        let heartFootmarkColor = CGColor(red: 0.92, green: 0.18, blue: 0.30, alpha: 1)
        // Solid fill — pattern CGColors are extremely expensive when painting
        // dozens of ellipses every frame on a transparent fullscreen window.
        let defaultFootmarkColor = CGColor(gray: 0.75, alpha: 0.55)
        for i in 0..<footMarks.count {
            let markTime = footMarks[i].time
            let markLifetime = footMarks[i].lifetime
            let fadeStart = markTime + markLifetime
            let fadeEnd = fadeStart + FootMark.ShrinkTime
            if markTime <= timeNow && timeNow <= fadeEnd {
                let fadeProgress = SamMath.Clamp((timeNow - fadeStart) / FootMark.ShrinkTime, 0, 1)
                let radius = SamMath.Lerp(3 * sizeScale, 0, fadeProgress)
                let markColor = footMarks[i].isHeartTrail ? heartFootmarkColor : defaultFootmarkColor
                FillCircleFromCenter(g, markColor, footMarks[i].position, Int(radius))
            }
        }
    }

    override func Render(_ param: Any) {
        let g = param as! CGContext
        g.scaleBy(x: 1, y: -1)
        g.scaleBy(x: CGFloat(sizeScale), y: CGFloat(sizeScale))
        // These 100/200 are the fixed base canvas size (pre-scale) — sizeScale
        // is applied above, not baked into these constants, or the dog would
        // drift off its actual position as the scale changes. See sizeScale.
        g.translateBy(x: CGFloat(100 - position.x), y: CGFloat(100 - position.y) - 200)
        UpdateRig()
        let vector2 = Vector2(1.3, 0.4)
        let fromAngleDegrees = Vector2.GetFromAngleDegrees(direction)
        let fromAngleDegrees2 = Vector2.GetFromAngleDegrees(direction + 90)
        let vector3 = Vector2(0, -1)
        let num: Float = 2
        g.setFillColor(settings.DogWhite)
        g.setLineCap(.round)
        FillCircleFromCenter(g, settings.DogOrange, lFootPos, 4)
        FillCircleFromCenter(g, settings.DogOrange, rFootPos, 4)
        g.setStrokeColor(settings.DogOutline)
        DrawLine(g, 22 + num, ToIntPoint(dogRig.bodyCenter + fromAngleDegrees * 11),
                              ToIntPoint(dogRig.bodyCenter - fromAngleDegrees * 11))
        DrawLine(g, 13 + num, ToIntPoint(dogRig.neckBase), ToIntPoint(dogRig.neckHeadPoint))
        DrawLine(g, 15 + num, ToIntPoint(dogRig.neckHeadPoint), ToIntPoint(dogRig.head1EndPoint))
        DrawLine(g, 10 + num, ToIntPoint(dogRig.head1EndPoint), ToIntPoint(dogRig.head2EndPoint))
        g.setStrokeColor(settings.DogOutline)
        DrawLine(g, 15, ToIntPoint(dogRig.underbodyCenter + fromAngleDegrees * 7),
                        ToIntPoint(dogRig.underbodyCenter - fromAngleDegrees * 7))
        g.setStrokeColor(settings.DogWhite)
        DrawLine(g, 22, ToIntPoint(dogRig.bodyCenter + fromAngleDegrees * 11),
                        ToIntPoint(dogRig.bodyCenter - fromAngleDegrees * 11))
        DrawLine(g, 13, ToIntPoint(dogRig.neckBase), ToIntPoint(dogRig.neckHeadPoint))
        DrawLine(g, 15, ToIntPoint(dogRig.neckHeadPoint), ToIntPoint(dogRig.head1EndPoint))
        DrawLine(g, 10, ToIntPoint(dogRig.head1EndPoint), ToIntPoint(dogRig.head2EndPoint))
        g.setStrokeColor(settings.DogOrange)
        let vector4 = dogRig.head2EndPoint + fromAngleDegrees * 5
        DrawLine(g, 9, ToIntPoint(dogRig.head2EndPoint), ToIntPoint(vector4))
        let baseEye = dogRig.neckHeadPoint + vector3 * 3 + fromAngleDegrees * 5
        let sideL = -fromAngleDegrees2 * vector2 * 5
        let sideR =  fromAngleDegrees2 * vector2 * 5
        let pos  = baseEye + sideL
        let pos2 = baseEye + sideR
        FillCircleFromCenter(g, settings.DogEye, pos, 2)
        FillCircleFromCenter(g, settings.DogEye, pos2, 2)
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
            let pool: [String] = files.isEmpty ? GitDog.ImageUrls : files
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
        guard !rect.isEmpty else { return }
        let p = CGPoint(x: rect.minX, y: rect.minY)
        // NabMouse calls this every frame; warping the cursor when it hasn't
        // meaningfully moved burns input/compositor time and feels like lag.
        if abs(p.x - lastCursorClipPoint.x) < 0.5 && abs(p.y - lastCursorClipPoint.y) < 0.5 {
            return
        }
        lastCursorClipPoint = p
        CGDisplayMoveCursorToPoint(CGMainDisplayID(), p)
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
