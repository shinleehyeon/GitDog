import AppKit
import CoreGraphics

final class BallWindow: NSWindow {
    var onLanded: ((Vector2) -> Void)?

    private let worldHeight: () -> CGFloat
    private let worldWidth: () -> CGFloat
    private static let size = CGSize(width: 32, height: 32)

    private var isDragging = false
    private var lastDragScreenPoint: NSPoint = .zero
    private var lastDragTime: TimeInterval = 0
    private var dragVelocity: CGVector = .zero

    private var flightTimer: Timer?
    private var flightStart: Vector2 = .zero
    private var flightLanding: Vector2 = .zero
    private var flightStartTime: TimeInterval = 0
    private static let flightDuration: TimeInterval = 0.5
    private static let hopHeight: CGFloat = 60
    private static let throwScale: Float = 0.35
    private static let maxThrowDistance: Float = 500

    init(worldPosition: Vector2, worldHeight: @escaping () -> CGFloat, worldWidth: @escaping () -> CGFloat) {
        self.worldHeight = worldHeight
        self.worldWidth = worldWidth
        let frame = CGRect(origin: .zero, size: Self.size)
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces]
        ignoresMouseEvents = false
        let ballView = BallView(frame: frame)
        ballView.ballWindow = self
        contentView = ballView
        place(at: worldPosition)
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var worldPosition: Vector2 {
        let h = worldHeight()
        return Vector2(Float(frame.midX), Float(h - frame.midY))
    }

    func setInteractive(_ interactive: Bool) {
        ignoresMouseEvents = !interactive
    }

    func place(at worldPosition: Vector2) {
        let h = worldHeight()
        let x = CGFloat(worldPosition.x) - frame.width * 0.5
        let y = h - CGFloat(worldPosition.y) - frame.height * 0.5
        setFrameOrigin(CGPoint(x: x, y: y))
    }

    func beginDrag(at screenPoint: NSPoint) {
        flightTimer?.invalidate()
        flightTimer = nil
        isDragging = true
        lastDragScreenPoint = screenPoint
        lastDragTime = ProcessInfo.processInfo.systemUptime
        dragVelocity = .zero
    }

    func continueDrag(to screenPoint: NSPoint) {
        guard isDragging else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(now - lastDragTime, 1.0 / 120.0)
        let dx = screenPoint.x - lastDragScreenPoint.x
        let dy = screenPoint.y - lastDragScreenPoint.y
        dragVelocity = CGVector(dx: dx / dt, dy: dy / dt)
        var origin = frame.origin
        origin.x += dx
        origin.y += dy
        setFrameOrigin(origin)
        lastDragScreenPoint = screenPoint
        lastDragTime = now
    }

    func endDrag() {
        guard isDragging else { return }
        isDragging = false
        let velocity = Vector2(Float(dragVelocity.dx), Float(-dragVelocity.dy))
        let start = worldPosition
        var landing = start + velocity * Self.throwScale
        if Vector2.Distance(start, landing) > Self.maxThrowDistance {
            let dir = (landing - start)
            let len = Vector2.Distance(start, landing)
            landing = start + dir * (Self.maxThrowDistance / max(len, 1))
        }
        let w = worldWidth()
        let h = worldHeight()
        landing.x = SamMath.Clamp(landing.x, Float(Self.size.width), Float(w) - Float(Self.size.width))
        landing.y = SamMath.Clamp(landing.y, Float(Self.size.height), Float(h) - Float(Self.size.height))
        startFlight(from: start, to: landing)
    }

    private func startFlight(from: Vector2, to: Vector2) {
        flightStart = from
        flightLanding = to
        flightStartTime = ProcessInfo.processInfo.systemUptime
        flightTimer?.invalidate()
        flightTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = ProcessInfo.processInfo.systemUptime - self.flightStartTime
            let p = min(Float(elapsed / Self.flightDuration), 1)
            let easedP = Easings.Interpolate(p, .QuadraticEaseOut)
            var current = Vector2.Lerp(self.flightStart, self.flightLanding, easedP)
            current.y -= Float(sin(Double(p) * .pi)) * Float(Self.hopHeight)
            self.place(at: current)
            if p >= 1 {
                timer.invalidate()
                self.flightTimer = nil
                self.place(at: self.flightLanding)
                self.onLanded?(self.flightLanding)
            }
        }
        RunLoop.main.add(flightTimer!, forMode: .common)
    }

    func dismiss() {
        flightTimer?.invalidate()
        flightTimer = nil
        orderOut(nil)
        close()
    }
}

private final class BallView: NSView {
    weak var ballWindow: BallWindow?
    private let label: NSTextField

    override init(frame: NSRect) {
        label = NSTextField(labelWithString: "🎾")
        super.init(frame: frame)
        label.font = NSFont.systemFont(ofSize: 24)
        label.alignment = .center
        label.frame = bounds
        label.autoresizingMask = [.width, .height]
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        ballWindow?.beginDrag(at: NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        ballWindow?.continueDrag(to: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        ballWindow?.endDrag()
    }
}
