// Port of: DogDesktop/GitDog.cs

import Foundation
import CoreGraphics

class GitDog {
    // Manual-only collect-window mode:
    // true  -> AI task picker can choose CollectWindow_* tasks
    // false -> collect windows run only when explicitly requested (hotkey/menu)
    private let allowAutomaticCollectWindows: Bool = false
    private let heartFootmarkLifetime: Float = 200
    // Re-enable occasional mouse nabbing, but keep it infrequent.
    private let allowOccasionalNabMouse: Bool = true
    enum SoundEffect {
        case CHOMP
        case MudSquith
        case HONCC
        case Pat
    }

    enum SpeedTiers {
        case Stroll   // slow amble
        case Walk
        case Run
        case Charge
    }

    enum GitDogTask: Int {
        case Wander
        case NabMouse
        case CollectWindow_Meme
        case CollectWindow_Notepad
        case CollectWindow_Donate
        case CollectWindow_DONOTSET
        case TrackMud
        case HeartTrail
        case BringFriends
        case Count
    }

    struct Task_Wander {
        static let MinPauseTime: Float = 1
        static let MaxPauseTime: Float = 2
        static let GoodEnoughDistance: Float = 20

        var wanderingStartTime: Float = 0
        var wanderingDuration: Float = 0
        var pauseStartTime: Float = 0
        var pauseDuration: Float = 0

        static func GetRandomPauseDuration() -> Float {
            // Moderate rests between wander legs — idles a fair bit, but not as
            // long as the old 2–6s stops.
            return 1.5 + SamMath.RandomRange(0, 1) * 2.5   // 1.5…4.0s
        }

        static func GetRandomWanderDuration() -> Float {
            if Time.time < 1 {
                return GitDogConfig.settings.FirstWanderTimeSeconds
            }
            return SamMath.RandomRange(GitDogConfig.settings.MinWanderingTimeSeconds,
                                       GitDogConfig.settings.MaxWanderingTimeSeconds)
        }

        static func GetRandomWalkTime() -> Float {
            return SamMath.RandomRange(1, 6)
        }
    }

    struct Task_NabMouse {
        enum Stage {
            case SeekingMouse
            case DraggingMouseAway
            case Decelerating
        }

        var currentStage: Stage = .SeekingMouse
        var dragToPoint: Vector2 = .zero
        var grabbedOriginalTime: Float = 0
        var chaseStartTime: Float = 0
        var originalVectorToMouse: Vector2 = .zero
        var hasSaidFrustrated: Bool = false

        static let MouseGrabDistance: Float = 15
        static let MouseSuccTime: Float = 0.06
        static let MouseDropDistance: Float = 30
        static let MinRunTime: Float = 2
        static let MaxRunTime: Float = 4
        static let GiveUpTime: Float = 9

        static let StruggleRange = Vector2(3, 3)
    }

    protocol IMovableForm: AnyObject {
        var Width: Int { get }
        var Height: Int { get }
        func Show(_ closeAction: @escaping () -> Void)
        func SetPosition(_ point: CGPoint)
    }

    struct Task_CollectWindow {
        enum Stage {
            case WalkingOffscreen
            case WaitingToBringWindowBack
            case DraggingWindowBack
        }

        enum ScreenDirection {
            case Left
            case Top
            case Right
        }

        var mainForm: IMovableForm?
        var stage: Stage = .WalkingOffscreen
        var secsToWait: Float = 0
        var waitStartTime: Float = 0
        var screenDirection: ScreenDirection = .Left
        var windowOffsetToBeak: Vector2 = .zero
        static func GetWaitTime() -> Float {
            return SamMath.RandomRange(2, 3.5)
        }
    }

    struct Task_TrackMud {
        enum Stage {
            case DecideToRun
            case RunningOffscreen
            case RunningWandering
        }

        static let DurationToRunAmok: Float = 2

        var nextDirChangeTime: Float = 0
        var timeToStopRunning: Float = 0
        var stage: Stage = .DecideToRun

        static func GetDirChangeInterval() -> Float {
            return 100
        }
    }

    struct Task_HeartTrail {
        var startTime: Float = 0
        var duration: Float = 12
        var center: Vector2 = .zero
        var xScale: Float = 7.5
        var yScale: Float = 6.0
        var isTracing: Bool = false
        var startPoint: Vector2 = .zero
    }

    struct Task_BringFriends {
        enum Stage {
            case WalkingOffscreen
            case WalkingBack
            case Chatting
        }
        var stage: Stage = .WalkingOffscreen
        var screenDirection: Task_CollectWindow.ScreenDirection = .Left
        var friendsFired: Bool = false
        var chatStartTime: Float = 0
        var chatFired: Bool = false
    }

    struct Rig {
        static let UnderBodyRadius: Int = 15
        static let UnderBodyLength: Int = 7
        static let UnderBodyElevation: Int = 9
        var underbodyCenter: Vector2 = .zero

        static let BodyRadius: Int = 22
        static let BodyLength: Int = 11
        static let BodyElevation: Int = 14
        var bodyCenter: Vector2 = .zero

        static let NeccRadius: Int = 13
        static let NeccHeight1: Int = 20
        static let NeccExtendForward1: Int = 3
        static let NeccHeight2: Int = 10
        static let NeccExtendForward2: Int = 16
        var neckLerpPercent: Float = 0
        var neckCenter: Vector2 = .zero
        var neckBase: Vector2 = .zero
        var neckHeadPoint: Vector2 = .zero

        static let HeadRadius1: Int = 15
        static let HeadLength1: Int = 3
        static let HeadRadius2: Int = 10
        static let HeadLength2: Int = 5
        var head1EndPoint: Vector2 = .zero
        var head2EndPoint: Vector2 = .zero

        static let EyeRadius: Int = 2
        static let EyeElevation: Int = 3
        static let IPD: Float = 5
        static let EyesForward: Float = 5
    }

    var inverseFrameRate: Float = 1.0 / 120.0

    private static let possiblePhrases: [String] = [
        "am goose hjonk",
        "good work",
        "nsfdafdsaafsdjl\r\nasdas       sorry\r\nhard to type withh feet",
        "i cause problems on purpose",
        "\"peace was never an option\"\r\n   -the goose (me)",
        "\r\n\r\n  >o) \r\n    (_>"
    ]

    private static let textIndices = Deck(possiblePhrases.count)

    var hasFootmarks: Bool = false

    var position: Vector2 = Vector2(300, 300)
    var velocity: Vector2 = Vector2(0, 0)
    var direction: Float = 90
    var targetDirection: Vector2 = .zero

    var overrideExtendNeck: Bool = false

    var targetPos: Vector2 = Vector2(300, 300)
    var targetDir: Float = 90

    // Uniform visual scale for the whole sprite (1.0 = original size). Kept on
    // the base class since both MacintoshGitDog's Render() and
    // ChickCharacterView's draw() need to read it through a `GitDog` reference.
    var sizeScale: Float = 1.0

    var currentSpeed: Float = 80
    var currentAcceleration: Float = 1300

    // Gentle, organic speed variation while en route — without this the dog
    // cruises at a dead-constant currentSpeed for the whole leg once it's up
    // to speed. Smoothly drifts toward a re-rolled target every couple of
    // seconds instead of jumping, so it reads as natural, not glitchy.
    private var speedVariation: Float = 1.0
    private var speedVariationTarget: Float = 1.0
    private var nextSpeedVariationRerollTime: Float = 0
    var stepTime: Float = 0.2

    static let WalkSpeed: Float = 80
    static let RunSpeed: Float = 200
    static let ChargeSpeed: Float = 400
    static let turnSpeed: Float = 120
    static let AccelerationNormal: Float = 1300
    static let AccelerationCharged: Float = 2300
    static let StopRadius: Float = -10
    static let StepTimeNormal: Float = 0.2
    static let StepTimeCharged: Float = 0.1

    var trackMudEndTime: Float = -1
    static let DurationToTrackMud: Float = 15

    var footMarks: [FootMark] = Array(repeating: FootMark(), count: 64)
    var footMarkIndex: Int = 0

    var lastFrameMouseButtonPressed: Bool = false

    // Click-to-rest: when true the dog sits still and ignores wandering/tasks.
    // Only the user can sit/wake the dog (by tapping it) — it never sits on its own.
    var isResting: Bool = false

    // Press-and-drag: hold the dog and move the cursor to carry it. A quick tap
    // (no drag) instead toggles resting.
    var isGrabbed: Bool = false
    private var mouseDownOnDog: Bool = false
    private var grabStartCursor: Vector2 = .zero
    private var grabOffset: Vector2 = .zero

    // Fling: releasing the mouse while dragging fast launches the dog on a
    // gravity-arced trajectory instead of just dropping it in place.
    private var lastGrabCursor: Vector2 = .zero
    private var throwVelocity: Vector2 = .zero
    private var isThrown: Bool = false
    private var throwStartY: Float = 0
    private static let throwGravity: Float = 1400
    private static let throwSpeedThreshold: Float = 250
    private static let maxThrowSpeed: Float = 800

    // Speech bubble shown above the dog (e.g. a "커밋해!" nudge). Read by the
    // character view each frame; cleared automatically when it expires.
    private(set) var speechText: String? = nil
    private var speechExpireTime: Float = 0

    private var currentTask: GitDogTask = .Wander
    private var pendingTask: GitDogTask? = nil
    private var taskWanderInfo = Task_Wander()
    private var taskNabMouseInfo = Task_NabMouse()
    private var tmpRect: CGRect = .zero
    private var tmpSize: CGSize = .zero
    private var taskCollectWindowInfo = Task_CollectWindow()
    private var taskTrackMudInfo = Task_TrackMud()
    private var taskHeartTrailInfo = Task_HeartTrail()
    static let nabMouseInterval: Float = 300  // 5 minutes
    private var nextAllowedNabMouseTime: Float = nabMouseInterval
    private var taskBringFriendsInfo = Task_BringFriends()
    private var nextAllowedBringFriendsTime: Float = 120
    var onBringFriendsReturning: (() -> Void)? = nil
    var onBringFriendsArrived: (() -> Void)? = nil
    var committedToday: Bool = false

    // Heavily meme-biased — user wanted the dog to bring memes much more often.
    // CanAttackAtRandom defaults to false, so the NabMouse slots are skipped by
    // ChooseNextTask anyway and effectively re-rolled.
    private var dogTaskWeightedList: [GitDogTask] = BehaviorSettings.shared.buildWeightedList()
    private var taskPickerDeck: Deck = Deck(BehaviorSettings.shared.buildWeightedList().count)

    var lFootPos: Vector2 = .zero
    var rFootPos: Vector2 = .zero
    var lFootMoveTimeStart: Float = -1
    var rFootMoveTimeStart: Float = -1
    var lFootMoveOrigin: Vector2 = .zero
    var rFootMoveOrigin: Vector2 = .zero
    var lFootMoveDir: Vector2 = .zero
    var rFootMoveDir: Vector2 = .zero

    static let wantStepAtDistance: Float = 5
    static let feetDistanceApart: Int = 6
    static let overshootFraction: Float = 0.4

    var dogRig = Rig()

    static let ImageUrls: [String] = []

    var ScheduledWanderTime: Float? = nil

    // When set, Wander targets this fixed position instead of picking random destinations.
    // Cleared automatically on arrival; setting a new one overrides any existing one.
    var lockedTarget: Vector2? = nil
    var onLockedTargetArrival: (() -> Void)? = nil

    // Curved wander: an intermediate arc waypoint offset perpendicularly from the
    // direct path. Set by beginWanderLeg() ~30% of the time; cleared on arrival.
    private var wanderArcWaypoint: Vector2? = nil

    // Walk directly to a destination, bypassing the Wander AI. Fires completion on arrival.
    func walkTo(_ dest: Vector2, onArrival: (() -> Void)? = nil) {
        lockedTarget = dest
        onLockedTargetArrival = onArrival
        ScheduledWanderTime = 9999
        SetTask(.Wander, honck: false)
    }

    // Waypoints for a hand-drawn path (see MacintoshGitDog's modifier+drag path
    // tracing). Walked one leg at a time by chaining walkTo's arrival callback.
    private var pathQueue: [Vector2] = []

    /// Walk through `points` in order, one leg at a time.
    func followPath(_ points: [Vector2]) {
        guard !points.isEmpty else { return }
        pathQueue = points
        advancePathQueue()
    }

    private func advancePathQueue() {
        guard !pathQueue.isEmpty else { return }
        let next = pathQueue.removeFirst()
        walkTo(next) { [weak self] in
            self?.advancePathQueue()
        }
    }

    init() {
        position = Vector2(-20, 120)
        targetPos = Vector2(100, 150)
        if !GitDogConfig.settings.CanAttackAtRandom {
            let memeOriginalIndex = dogTaskWeightedList.firstIndex(of: .CollectWindow_Meme) ?? 0
            let num = taskPickerDeck.indices.firstIndex(of: memeOriginalIndex) ?? 0
            let num2 = taskPickerDeck.indices[0]
            taskPickerDeck.indices[0] = taskPickerDeck.indices[num]
            taskPickerDeck.indices[num] = num2
        }
        lFootPos = GetFootHome(rightFoot: false)
        rFootPos = GetFootHome(rightFoot: true)
        SetTask(.Wander)
    }

    private func SetSpeed(_ tier: SpeedTiers) {
        switch tier {
        case .Stroll:
            currentSpeed = 38
            currentAcceleration = 900
            stepTime = 0.32
        case .Walk:
            currentSpeed = 80
            currentAcceleration = 1300
            stepTime = 0.2
        case .Run:
            currentSpeed = 200
            currentAcceleration = 1300
            stepTime = 0.2
        case .Charge:
            currentSpeed = 400
            currentAcceleration = 2300
            stepTime = 0.1
        }
    }

    func IsLeftMouseDown() -> Bool {
        fatalError("abstract")
    }

    func SetCursorClip(_ rect: CGRect) {
        fatalError("abstract")
    }

    func Render(_ param: Any) {
        fatalError("abstract")
    }

    // Show a speech bubble above the dog for `duration` seconds. Every line the
    // dog says ends with a "ㅋㅋ" for a cheeky tone.
    func Say(_ text: String, duration: Float = 4) {
        speechText = text.hasSuffix("ㅋㅋ") ? text : text + "ㅋㅋ"
        speechExpireTime = Time.time + duration
    }

    func Tick() {
        let prevPosition = position
        SetCursorClip(.zero)
        if speechText != nil && Time.time > speechExpireTime {
            speechText = nil
        }
        // Pressing on the dog starts a potential grab. Dragging the cursor
        // picks the dog up and carries it; a quick tap (no drag) instead toggles
        // resting (sit & stop / wake up).
        let mouseDown = IsLeftMouseDown()
        let cursor = GetCursorPosition()
        // Hit-test radius scales with the sprite so bigger dogs stay easy to
        // click and small ones don't get an oversized grab area.
        let overDog = Vector2.Distance(position + Vector2(0, 14) * sizeScale, cursor) < 30 * sizeScale
        if mouseDown && !lastFrameMouseButtonPressed && overDog {
            mouseDownOnDog = true
            grabStartCursor = cursor
            grabOffset = position - cursor
            lastGrabCursor = cursor
            throwVelocity = .zero
        }
        if mouseDown && mouseDownOnDog {
            if !isGrabbed && Vector2.Distance(cursor, grabStartCursor) > 6 {
                isGrabbed = true
                isResting = false
            }
            if isGrabbed {
                // Trail behind the cursor instead of snapping to it instantly —
                // reads as a soft, animated drag rather than a rigid attach.
                position = Vector2.Lerp(position, cursor + grabOffset, 0.35)
                velocity = .zero
                // Track release velocity from the cursor's own motion (not the
                // lerped position) so a fast fling reads as fast even though
                // the body itself trails behind smoothly.
                let instantVelocity = (cursor - lastGrabCursor) / inverseFrameRate
                throwVelocity = Vector2.Lerp(throwVelocity, instantVelocity, 0.5)
                lastGrabCursor = cursor
            }
        }
        if !mouseDown && lastFrameMouseButtonPressed {
            if isGrabbed {
                isGrabbed = false
                let flingSpeed = Vector2.Magnitude(throwVelocity)
                if flingSpeed > Self.throwSpeedThreshold {
                    // Flung — launch on a gravity-arced trajectory. Damped and
                    // capped so a fast flick doesn't send it rocketing off.
                    isThrown = true
                    let launchSpeed = min(flingSpeed * 0.85, Self.maxThrowSpeed)
                    velocity = Vector2.Normalize(throwVelocity) * launchSpeed
                    throwStartY = position.y
                } else {
                    // Gently dropped — carry on wandering from the new spot.
                    targetPos = position
                    SetTask(.Wander, honck: false)
                }
            } else if mouseDownOnDog {
                // A tap → toggle sit/stop.
                isResting.toggle()
                velocity = .zero
                if isResting { targetPos = position } else { SetTask(.Wander, honck: false) }
            }
            mouseDownOnDog = false
        }
        lastFrameMouseButtonPressed = mouseDown

        // While held by the cursor, the position already follows it — freeze AI.
        if isGrabbed {
            velocity = .zero
            // SolveFeet()'s normal walking-gait stepping (one foot at a time,
            // small per-step distance) can't keep up with how far the body
            // jumps per frame while being dragged, so the feet visibly detach
            // and trail behind. Keep them anchored under the body, but add a
            // small alternating paddle so it reads as a dangling kick rather
            // than frozen/static feet.
            let dir = Vector2.GetFromAngleDegrees(direction)
            let paddle = sin(Time.time * 14) * 4
            lFootPos = GetFootHome(rightFoot: false) + dir * paddle
            rFootPos = GetFootHome(rightFoot: true) - dir * paddle
            lFootMoveTimeStart = -1
            rFootMoveTimeStart = -1
            SolveFeet()
            return
        }
        // While resting, freeze in place: no AI, no movement — just keep the rig
        // solved so the sitting pose renders cleanly. Only a user tap wakes it.
        if isResting {
            velocity = .zero
            targetPos = position
            SolveFeet()
            return
        }
        // Airborne after a fling: integrate gravity until it comes back down
        // to about the height it was thrown from (or the bottom edge,
        // whichever it hits first), then land and resume normal AI.
        if isThrown {
            velocity.y += Self.throwGravity * inverseFrameRate
            position += velocity * inverseFrameRate
            // Never leave the screen — clamp on all sides while airborne.
            position.x = SamMath.Clamp(position.x, 0, GetMainWindowWidth())
            position.y = max(position.y, 0)
            // Fall a solid distance past the launch height (not all the way
            // to the very bottom every time — that read as too much) unless
            // the screen bottom is closer, so it never lands off-screen.
            let landingY = min(throwStartY + 220, GetMainWindowHeight())
            if velocity.y > 0 && position.y >= landingY {
                isThrown = false
                position.y = min(position.y, GetMainWindowHeight())
                velocity = .zero
                targetPos = position
                SetTask(.Wander, honck: false)
                // Landed — fall through to normal AI/foot-solve below.
            } else {
                let dir = Vector2.GetFromAngleDegrees(direction)
                let paddle = sin(Time.time * 14) * 4
                lFootPos = GetFootHome(rightFoot: false) + dir * paddle
                rFootPos = GetFootHome(rightFoot: true) - dir * paddle
                lFootMoveTimeStart = -1
                rFootMoveTimeStart = -1
                SolveFeet()
                return
            }
        }
        // Set default targetDirection forward; RunAI may override it (e.g.
        // DraggingWindowBack reverses it so the dog walks in backwards).
        let toTarget = targetPos - position
        if Vector2.Magnitude(toTarget) > 1.0 {
            targetDirection = Vector2.Normalize(toTarget)
        }
        overrideExtendNeck = false
        RunAI()
        // Use whatever targetDirection RunAI left (forward or reversed).
        // Guard against zero vector: when frozen at target, skip direction
        // update so direction doesn't drift back to 0° every frame.
        if Vector2.Magnitude(targetDirection) > 0.1 {
            let targetAngle = atan2(targetDirection.y, targetDirection.x) * (180 / .pi)
            var angleDelta = targetAngle - direction
            if angleDelta >  180 { angleDelta -= 360 }
            if angleDelta < -180 { angleDelta += 360 }
            direction += angleDelta * 0.25
        }
        // During a wander pause, freeze completely. Otherwise the per-frame
        // acceleration toward the (near-but-not-reached) target keeps nudging
        // the position, which reads as a jitter/tremble while "standing still".
        let pausedStill = (currentTask == .Wander && taskWanderInfo.pauseStartTime > 0)
        if pausedStill {
            velocity = .zero
        } else {
            if Time.time >= nextSpeedVariationRerollTime {
                speedVariationTarget = SamMath.RandomRange(0.85, 1.15)
                nextSpeedVariationRerollTime = Time.time + SamMath.RandomRange(1.5, 3.0)
            }
            speedVariation = SamMath.Lerp(speedVariation, speedVariationTarget, 0.05)
            let effectiveSpeed = currentSpeed * speedVariation
            if Vector2.Magnitude(velocity) > effectiveSpeed {
                velocity = Vector2.Normalize(velocity) * effectiveSpeed
            }
            velocity += Vector2.Normalize(targetPos - position) * currentAcceleration * (1.0 / 120.0)
            position += velocity * inverseFrameRate
        }
        if currentTask == .HeartTrail && taskHeartTrailInfo.isTracing {
            position = targetPos
            velocity = .zero
            let delta = position - prevPosition
            if Vector2.Magnitude(delta) > 0.001 {
                direction = atan2(delta.y, delta.x) * (180 / .pi)
            }
            sanitizeFeetForHeartTrail()
        }
        SolveFeet()
        _ = Vector2.Magnitude(velocity)
        let num: Float = (overrideExtendNeck || (currentSpeed >= 200)) ? 1 : 0
        dogRig.neckLerpPercent = SamMath.Lerp(dogRig.neckLerpPercent, num, 0.075)
    }

    func GetMainWindowWidth() -> Float { fatalError("abstract") }
    func GetMainWindowHeight() -> Float { fatalError("abstract") }

    private func RunWander() {
        // Gang-mode: bypass normal Wander AI and walk directly to a fixed destination.
        if let dest = lockedTarget {
            targetPos = dest
            if Vector2.Distance(position, dest) < 20, let cb = onLockedTargetArrival {
                lockedTarget = nil
                onLockedTargetArrival = nil
                cb()
                // If the callback re-set lockedTarget, the next frame picks it up.
            }
            return
        }

        if Time.time - taskWanderInfo.wanderingStartTime > taskWanderInfo.wanderingDuration {
            ChooseNextTask()
        } else if taskWanderInfo.pauseStartTime > 0 {
            if Time.time - taskWanderInfo.pauseStartTime > taskWanderInfo.pauseDuration {
                taskWanderInfo.pauseStartTime = -1
                beginWanderLeg()
            } else {
                velocity = .zero
            }
        } else {
            // If there's an arc waypoint, head there first; clear it on arrival.
            if let wp = wanderArcWaypoint {
                if Vector2.Distance(position, wp) < 20 {
                    wanderArcWaypoint = nil
                } else {
                    targetPos = wp
                    return
                }
            }
            if Vector2.Distance(position, targetPos) < 20 {
                // Take a rest fairly often so the dog idles a good amount between
                // its wander legs.
                if SamMath.RandomRange(0, 1) < 0.6 {
                    taskWanderInfo.pauseStartTime = Time.time
                    taskWanderInfo.pauseDuration = Task_Wander.GetRandomPauseDuration()
                } else {
                    beginWanderLeg()
                }
            }
        }
    }

    // Start a new wander leg: pick a pace and a fresh target to walk toward.
    private func beginWanderLeg() {
        // Vary the pace each leg — an even mix of slow stroll and quicker walk.
        SetSpeed(SamMath.RandomRange(0, 1) < 0.5 ? .Stroll : .Walk)
        let num = Task_Wander.GetRandomWalkTime() * currentSpeed
        targetPos = Vector2(SamMath.RandomRange(0, GetMainWindowWidth()),
                            SamMath.RandomRange(0, GetMainWindowHeight()))
        if Vector2.Distance(position, targetPos) > num {
            targetPos = position + Vector2.Normalize(targetPos - position) * num
        }

        // ~30% chance: add a perpendicular arc waypoint so the dog curves
        // rather than walking in a straight line.
        wanderArcWaypoint = nil
        if SamMath.RandomRange(0, 1) < 0.3 {
            let direct = Vector2.Normalize(targetPos - position)
            let perp = Vector2(-direct.y, direct.x)
            let side: Float = SamMath.RandomRange(0, 1) < 0.5 ? 1 : -1
            let dist = SamMath.RandomRange(60, 160) * side
            let mid = (position + targetPos) * 0.5
            let wp = mid + perp * dist
            // Only use the waypoint if it stays on screen.
            let w = GetMainWindowWidth(); let h = GetMainWindowHeight()
            if wp.x > 0 && wp.x < w && wp.y > 0 && wp.y < h {
                wanderArcWaypoint = wp
            }
        }
    }

    func GetCursorPosition() -> Vector2 { fatalError("abstract") }
    func BringWindowToForeground() { fatalError("abstract") }
    func PlaySound(_ sound: SoundEffect) { fatalError("abstract") }

    private func RunNabMouse() {
        let cursorPosition = GetCursorPosition()
        let head2EndPoint = dogRig.head2EndPoint
        if taskNabMouseInfo.currentStage == .SeekingMouse {
            SetSpeed(.Charge)
            targetPos = cursorPosition - (dogRig.head2EndPoint - position)
            if Vector2.Distance(head2EndPoint, cursorPosition) < 15 {
                taskNabMouseInfo.originalVectorToMouse = cursorPosition - head2EndPoint
                taskNabMouseInfo.grabbedOriginalTime = Time.time
                taskNabMouseInfo.dragToPoint = position
                while Vector2.Distance(taskNabMouseInfo.dragToPoint, position) / 400 < 1.2 {
                    taskNabMouseInfo.dragToPoint = Vector2(
                        SamMath.RandomRange(0, 1) * GetMainWindowWidth(),
                        SamMath.RandomRange(0, 1) * GetMainWindowHeight()
                    )
                }
                targetPos = taskNabMouseInfo.dragToPoint
                BringWindowToForeground()
                PlaySound(.CHOMP)
                taskNabMouseInfo.currentStage = .DraggingMouseAway
            }
            if !taskNabMouseInfo.hasSaidFrustrated && Time.time > taskNabMouseInfo.chaseStartTime + 5 {
                taskNabMouseInfo.hasSaidFrustrated = true
                Say("아오 좀 멈춰봐")
            }
            if Time.time > taskNabMouseInfo.chaseStartTime + 9 {
                taskNabMouseInfo.currentStage = .Decelerating
            }
        }
        if taskNabMouseInfo.currentStage == .DraggingMouseAway {
            if Vector2.Distance(position, targetPos) < 30 {
                SetCursorClip(.zero)
                taskNabMouseInfo.currentStage = .Decelerating
            } else {
                let p = min((Time.time - taskNabMouseInfo.grabbedOriginalTime) / 0.06, 1)
                let vector = Vector2.Lerp(taskNabMouseInfo.originalVectorToMouse, Task_NabMouse.StruggleRange, p)
                let originX: Float = vector.x < 0 ? head2EndPoint.x + vector.x : head2EndPoint.x
                let originY: Float = vector.y < 0 ? head2EndPoint.y + vector.y : head2EndPoint.y
                tmpRect.origin = CGPoint(x: CGFloat(originX), y: CGFloat(originY))
                tmpSize.width  = CGFloat(abs(Int(vector.x)))
                tmpSize.height = CGFloat(abs(Int(vector.y)))
                tmpRect.size = tmpSize
                SetCursorClip(tmpRect)
            }
        }
        if taskNabMouseInfo.currentStage == .Decelerating {
            targetPos = position + Vector2.Normalize(velocity) * 5
            velocity -= Vector2.Normalize(velocity) * currentAcceleration * 2 * inverseFrameRate
            if Vector2.Magnitude(velocity) < 80 {
                SetTask(.Wander)
            }
        }
    }

    private func RunCollectWindow() {
        switch taskCollectWindowInfo.stage {
        case .WalkingOffscreen:
            if Vector2.Distance(position, targetPos) < 20 {
                taskCollectWindowInfo.secsToWait = Task_CollectWindow.GetWaitTime()
                taskCollectWindowInfo.waitStartTime = Time.time
                taskCollectWindowInfo.stage = .WaitingToBringWindowBack
            }
        case .WaitingToBringWindowBack:
            if Time.time - taskCollectWindowInfo.waitStartTime > taskCollectWindowInfo.secsToWait {
                taskCollectWindowInfo.mainForm?.Show(CancelWindowTracking)
                if let form = taskCollectWindowInfo.mainForm {
                    switch taskCollectWindowInfo.screenDirection {
                    case .Left:
                        targetPos.y = SamMath.Lerp(position.y, GetMainWindowHeight() / 2,
                                                   SamMath.RandomRange(0.2, 0.3))
                        targetPos.x = Float(form.Width) + SamMath.RandomRange(15, 20)
                    case .Top:
                        targetPos.y = Float(form.Height) + SamMath.RandomRange(80, 100)
                        targetPos.x = SamMath.Lerp(position.x, GetMainWindowWidth() / 2,
                                                   SamMath.RandomRange(0.2, 0.3))
                    case .Right:
                        targetPos.y = SamMath.Lerp(position.y, GetMainWindowHeight() / 2,
                                                   SamMath.RandomRange(0.2, 0.3))
                        targetPos.x = GetMainWindowWidth() - (Float(form.Width) + SamMath.RandomRange(20, 30))
                    }
                    targetPos.x = SamMath.Clamp(targetPos.x, Float(form.Width + 55),
                                                GetMainWindowWidth() - Float(form.Width + 55))
                    targetPos.y = SamMath.Clamp(targetPos.y, Float(form.Height + 80), GetMainWindowHeight())
                }
                taskCollectWindowInfo.stage = .DraggingWindowBack
            }
        case .DraggingWindowBack:
            if Vector2.Distance(position, targetPos) < 5 {
                targetPos = position + Vector2.GetFromAngleDegrees(direction + 180) * 40
                SetTask(.Wander)
            } else {
                overrideExtendNeck = true
                targetDirection = position - targetPos
                let p = dogRig.head2EndPoint - taskCollectWindowInfo.windowOffsetToBeak
                taskCollectWindowInfo.mainForm?.SetPosition(ToIntPoint(p))
            }
        }
    }

    private func CancelWindowTracking() {
        SetTask(.NabMouse)
    }

    private func RunTrackMud() {
        switch taskTrackMudInfo.stage {
        case .DecideToRun:
            _ = SetTargetOffscreen()
            SetSpeed(.Run)
            taskTrackMudInfo.stage = .RunningOffscreen
        case .RunningOffscreen:
            if Vector2.Distance(position, targetPos) < 5 {
                targetPos = Vector2(SamMath.RandomRange(0, GetMainWindowWidth()),
                                    SamMath.RandomRange(0, GetMainWindowHeight()))
                taskTrackMudInfo.nextDirChangeTime = Time.time + Task_TrackMud.GetDirChangeInterval()
                taskTrackMudInfo.timeToStopRunning = Time.time + 2
                trackMudEndTime = Time.time + 15
                taskTrackMudInfo.stage = .RunningWandering
                PlaySound(.MudSquith)
            }
        case .RunningWandering:
            if Vector2.Distance(position, targetPos) < 5 || Time.time > taskTrackMudInfo.nextDirChangeTime {
                targetPos = Vector2(SamMath.RandomRange(0, GetMainWindowWidth()),
                                    SamMath.RandomRange(0, GetMainWindowHeight()))
                taskTrackMudInfo.nextDirChangeTime = Time.time + Task_TrackMud.GetDirChangeInterval()
            }
            if Time.time > taskTrackMudInfo.timeToStopRunning {
                targetPos = position + Vector2(30, 3)
                targetPos.x = SamMath.Clamp(targetPos.x, 55, GetMainWindowWidth() - 55)
                targetPos.y = SamMath.Clamp(targetPos.y, 80, GetMainWindowHeight() - 80)
                SetTask(.Wander, honck: false)
            }
        }
    }

    private func RunHeartTrail() {
        SetSpeed(.Charge)
        if !taskHeartTrailInfo.isTracing {
            // First, run to the heart start point naturally (no teleport).
            targetPos = taskHeartTrailInfo.startPoint
            if Vector2.Distance(position, taskHeartTrailInfo.startPoint) <= 20 {
                taskHeartTrailInfo.isTracing = true
                taskHeartTrailInfo.startTime = Time.time
                let commitLines = ["커밋 ㅊㅊ", "오 커밋했네\nㄷㄷ", "잔디\n심었다ㅋ", "커밋\n했구만ㅋ"]
                Say(commitLines.randomElement()!, duration: 3.0)
                targetPos = heartPoint(progress: 0, center: taskHeartTrailInfo.center,
                                       xScale: taskHeartTrailInfo.xScale, yScale: taskHeartTrailInfo.yScale)
            }
            return
        }
        let elapsed = Time.time - taskHeartTrailInfo.startTime
        if elapsed >= taskHeartTrailInfo.duration {
            // Linger on the spot for 2s before wandering off again.
            SetTask(.Wander, honck: false)
            taskWanderInfo.pauseStartTime = Time.time
            taskWanderInfo.pauseDuration = 2
            targetPos = position
            velocity = .zero
            return
        }
        let p = elapsed / taskHeartTrailInfo.duration
        targetPos = heartPoint(progress: p, center: taskHeartTrailInfo.center,
                               xScale: taskHeartTrailInfo.xScale, yScale: taskHeartTrailInfo.yScale)
    }

    private func RunBringFriends() {
        switch taskBringFriendsInfo.stage {
        case .WalkingOffscreen:
            if Vector2.Distance(position, targetPos) < 20 {
                let w = GetMainWindowWidth()
                let h = GetMainWindowHeight()
                let edgeInset: Float = 200
                switch taskBringFriendsInfo.screenDirection {
                case .Left:
                    targetPos = Vector2(edgeInset, SamMath.Clamp(position.y, 100, h - 100))
                case .Right:
                    targetPos = Vector2(w - edgeInset, SamMath.Clamp(position.y, 100, h - 100))
                case .Top:
                    targetPos = Vector2(SamMath.Clamp(position.x, 100, w - 100), edgeInset)
                }
                taskBringFriendsInfo.stage = .WalkingBack
                SetSpeed(.Run)
                currentSpeed = 130
                if !taskBringFriendsInfo.friendsFired {
                    taskBringFriendsInfo.friendsFired = true
                    onBringFriendsReturning?()
                }
            }
        case .WalkingBack:
            if Vector2.Distance(position, targetPos) < 20 {
                velocity = .zero
                targetPos = position
                taskBringFriendsInfo.stage = .Chatting
                taskBringFriendsInfo.chatStartTime = Time.time
            }
        case .Chatting:
            // Face downward and freeze while talking.
            targetPos = position
            velocity = .zero
            targetDirection = Vector2(0, 1)
            if !taskBringFriendsInfo.chatFired {
                taskBringFriendsInfo.chatFired = true
                Say("얘임 커밋\n하나도 안한애가", duration: 4.0)
                onBringFriendsArrived?()
            }
            if Time.time - taskBringFriendsInfo.chatStartTime > 13 {
                SetTask(.Wander, honck: false)
            }
        }
    }

    private func ChooseNextTask() {
        if !GitDogConfig.settings.CanAttackAtRandom && Time.time < GitDogConfig.settings.FirstWanderTimeSeconds + 1 {
            // Keep startup in normal random wander; avoid forced offscreen run.
            SetTask(.Wander, honck: false)
            return
        }
        if allowOccasionalNabMouse && Time.time >= nextAllowedNabMouseTime {
            // Fixed interval — nabs the mouse every 5 minutes, not randomly.
            nextAllowedNabMouseTime = Time.time + Self.nabMouseInterval
            SetTask(.NabMouse, honck: false)
            return
        }
        let friendsWeight = BehaviorSettings.shared.friendsWeight
        if friendsWeight > 0 && !committedToday && Time.time >= nextAllowedBringFriendsTime {
            let friendsProb = Float(friendsWeight) * 0.10  // 0.10 … 0.50
            if SamMath.RandomRange(0, 1) < friendsProb {
                nextAllowedBringFriendsTime = Time.time + 60
                SetTask(.BringFriends, honck: false)
                return
            }
            nextAllowedBringFriendsTime = Time.time + 60
        }
        // Prevent hangs: if all weighted tasks are filtered out, fallback to Wander.
        for _ in 0..<(dogTaskWeightedList.count * 3) {
            let dogTask = dogTaskWeightedList[taskPickerDeck.Next()]
            let blockedCollect = !allowAutomaticCollectWindows && isAutomaticCollectWindowTask(dogTask)
            if blockedCollect {
                continue
            }
            SetTask(dogTask)
            return
        }
        SetTask(.Wander, honck: false)
    }

    func CreateImageForm() -> IMovableForm { fatalError("abstract") }
    func CreateTextForm(_ title: String, _ note: String) -> IMovableForm { fatalError("abstract") }
    func CreateDonateForm() -> IMovableForm { fatalError("abstract") }

    func GetNextNote() -> String {
        return GitDog.possiblePhrases[GitDog.textIndices.Next()]
    }

    // External callers use requestTask — it queues the task if the dog
    // is currently mid-action and applies it when Wander is re-entered.
    func rebuildBehaviorWeights() {
        let list = BehaviorSettings.shared.buildWeightedList()
        dogTaskWeightedList = list
        taskPickerDeck = Deck(list.count)
    }

    func requestTask(_ task: GitDogTask) {
        guard currentTask != .BringFriends else { return }
        guard currentTask == .Wander else {
            pendingTask = task
            return
        }
        SetTask(task, honck: false)
    }

    func SetTask(_ task: GitDogTask, honck: Bool = true) {
        if honck {
            PlaySound(.HONCC)
        }
        currentTask = task
        switch task {
        case .Wander:
            SetSpeed(.Walk)
            taskWanderInfo = Task_Wander()
            taskWanderInfo.pauseStartTime = -1
            taskWanderInfo.wanderingStartTime = Time.time
            taskWanderInfo.wanderingDuration = ScheduledWanderTime ?? Task_Wander.GetRandomWanderDuration()
            ScheduledWanderTime = nil
            if let next = pendingTask {
                pendingTask = nil
                SetTask(next, honck: false)
                return
            }
        case .NabMouse:
            taskNabMouseInfo = Task_NabMouse()
            taskNabMouseInfo.chaseStartTime = Time.time
        case .CollectWindow_Meme:
            taskCollectWindowInfo = Task_CollectWindow()
            taskCollectWindowInfo.mainForm = CreateImageForm()
            SetTask(.CollectWindow_DONOTSET, honck: false)
        case .CollectWindow_Notepad:
            taskCollectWindowInfo = Task_CollectWindow()
            taskCollectWindowInfo.mainForm = CreateTextForm("GitDog \"Not-epad\"", GetNextNote())
            SetTask(.CollectWindow_DONOTSET, honck: false)
        case .CollectWindow_Donate:
            // Donation window feature is disabled.
            SetTask(.Wander, honck: false)
        case .CollectWindow_DONOTSET:
            taskCollectWindowInfo.screenDirection = SetTargetOffscreen()
            if let form = taskCollectWindowInfo.mainForm {
                switch taskCollectWindowInfo.screenDirection {
                case .Left:
                    taskCollectWindowInfo.windowOffsetToBeak = Vector2(Float(form.Width), Float(form.Height / 2))
                case .Top:
                    taskCollectWindowInfo.windowOffsetToBeak = Vector2(Float(form.Width / 2), Float(form.Height))
                case .Right:
                    taskCollectWindowInfo.windowOffsetToBeak = Vector2(0, Float(form.Height / 2))
                }
            }
        case .BringFriends:
            taskBringFriendsInfo = Task_BringFriends()
            taskBringFriendsInfo.screenDirection = SetTargetOffscreen()
            // Push exit target far enough that the dog is fully invisible (view is 200px wide).
            switch taskBringFriendsInfo.screenDirection {
            case .Left:  targetPos.x -= 150
            case .Right: targetPos.x += 150
            case .Top:   targetPos.y -= 150
            }
        case .TrackMud:
            // Disable TrackMud so offscreen travel happens only for image/note collect.
            SetTask(.Wander, honck: false)
        case .HeartTrail:
            taskHeartTrailInfo = Task_HeartTrail()
            let w = GetMainWindowWidth()
            let h = GetMainWindowHeight()
            // Heart equation spans about x:[-16,16], y:[-17,13].
            // Auto-fit with margins so the whole curve stays visible.
            let xScaleLimit = max(4, (w - 180) / 32)
            let yScaleLimit = max(4, (h - 240) / 30)
            let scale = min(xScaleLimit, yScaleLimit)
            taskHeartTrailInfo.xScale = scale
            taskHeartTrailInfo.yScale = scale
            // Center the heart in screen space.
            taskHeartTrailInfo.center = Vector2(w * 0.5, h * 0.56)
            taskHeartTrailInfo.isTracing = false
            taskHeartTrailInfo.startPoint = heartPoint(progress: 0, center: taskHeartTrailInfo.center,
                                                       xScale: taskHeartTrailInfo.xScale, yScale: taskHeartTrailInfo.yScale)
            targetPos = taskHeartTrailInfo.startPoint
        case .Count:
            break
        }
    }

    private func RunAI() {
        switch currentTask {
        case .Wander:                  RunWander()
        case .NabMouse:                RunNabMouse()
        case .CollectWindow_DONOTSET:  RunCollectWindow()
        case .TrackMud:                RunTrackMud()
        case .HeartTrail:              RunHeartTrail()
        case .BringFriends:            RunBringFriends()
        case .CollectWindow_Meme, .CollectWindow_Notepad, .CollectWindow_Donate,
             .Count:
            break
        }
    }

    private func isAutomaticCollectWindowTask(_ task: GitDogTask) -> Bool {
        task == .CollectWindow_Meme
            || task == .CollectWindow_Notepad
            || task == .CollectWindow_Donate
    }

    private func heartPoint(progress p: Float, center: Vector2, xScale: Float, yScale: Float) -> Vector2 {
        let theta = p * 2 * Float.pi
        let sinT = sin(theta)
        let cosT = cos(theta)
        let x = 16 * sinT * sinT * sinT
        let y = 13 * cosT - 5 * cos(2 * theta) - 2 * cos(3 * theta) - cos(4 * theta)
        return center + Vector2(x * xScale, -y * yScale)
    }

    private func SetTargetOffscreen(canExitTop: Bool = false) -> Task_CollectWindow.ScreenDirection {
        var num = Int(position.x)
        var result: Task_CollectWindow.ScreenDirection = .Left
        targetPos = Vector2(-50, SamMath.Lerp(position.y, GetMainWindowHeight() / 2, 0.4))
        if Float(num) > GetMainWindowWidth() / 2 {
            num = Int(GetMainWindowWidth()) - Int(position.x)
            result = .Right
            targetPos = Vector2(GetMainWindowWidth() + 50,
                                SamMath.Lerp(position.y, GetMainWindowHeight() / 2, 0.4))
        }
        if canExitTop && Float(num) > position.y {
            result = .Top
            targetPos = Vector2(SamMath.Lerp(position.x, GetMainWindowWidth() / 2, 0.4), -50)
        }
        return result
    }

    private func SolveFeet() {
        _ = Vector2.GetFromAngleDegrees(direction)
        _ = Vector2.GetFromAngleDegrees(direction + 90)
        let footHome  = GetFootHome(rightFoot: false)
        let footHome2 = GetFootHome(rightFoot: true)
        if lFootMoveTimeStart < 0 && rFootMoveTimeStart < 0 {
            if Vector2.Distance(lFootPos, footHome) > 5 {
                lFootMoveOrigin = lFootPos
                lFootMoveDir = Vector2.Normalize(footHome - lFootPos)
                lFootMoveTimeStart = Time.time
            } else if Vector2.Distance(rFootPos, footHome2) > 5 {
                rFootMoveOrigin = rFootPos
                rFootMoveDir = Vector2.Normalize(footHome2 - rFootPos)
                rFootMoveTimeStart = Time.time
            }
        } else if lFootMoveTimeStart > 0 {
            let b = footHome + lFootMoveDir * 0.4 * 5
            if Time.time <= lFootMoveTimeStart + stepTime {
                let p = (Time.time - lFootMoveTimeStart) / stepTime
                lFootPos = Vector2.Lerp(lFootMoveOrigin, b, Easings.CubicEaseInOut(p))
                return
            }
            lFootPos = b
            lFootMoveTimeStart = -1
            PlaySound(.Pat)
            AddFootMark(lFootPos,
                        lifetime: currentTask == .HeartTrail ? heartFootmarkLifetime : FootMark.Lifetime,
                        isHeartTrail: currentTask == .HeartTrail)
        } else {
            if rFootMoveTimeStart <= 0 { return }
            let b2 = footHome2 + rFootMoveDir * 0.4 * 5
            if Time.time > rFootMoveTimeStart + stepTime {
                rFootPos = b2
                rFootMoveTimeStart = -1
                PlaySound(.Pat)
                AddFootMark(rFootPos,
                            lifetime: currentTask == .HeartTrail ? heartFootmarkLifetime : FootMark.Lifetime,
                            isHeartTrail: currentTask == .HeartTrail)
            } else {
                let p2 = (Time.time - rFootMoveTimeStart) / stepTime
                rFootPos = Vector2.Lerp(rFootMoveOrigin, b2, Easings.CubicEaseInOut(p2))
            }
        }
    }

    private func GetFootHome(rightFoot: Bool) -> Vector2 {
        let num: Float = rightFoot ? 1 : 0
        let vector = Vector2.GetFromAngleDegrees(direction + 90) * num
        return position + vector * 6
    }

    private func AddFootMark(_ markPos: Vector2,
                             lifetime: Float = FootMark.Lifetime,
                             isHeartTrail: Bool = false) {
        // Heart trail marks should appear immediately; normal marks keep delay.
        footMarks[footMarkIndex].time = isHeartTrail ? Time.time : (Time.time + 0.5)
        footMarks[footMarkIndex].position = markPos
        footMarks[footMarkIndex].lifetime = lifetime
        footMarks[footMarkIndex].isHeartTrail = isHeartTrail
        footMarkIndex += 1
        hasFootmarks = true
        if footMarkIndex >= footMarks.count {
            footMarkIndex = 0
        }
    }

    private func sanitizeFeetForHeartTrail() {
        let leftHome = GetFootHome(rightFoot: false)
        let rightHome = GetFootHome(rightFoot: true)
        // Heart mode teleports position; if a foot drifts too far, snap it back once.
        if Vector2.Distance(lFootPos, leftHome) > 24 {
            lFootPos = leftHome
            lFootMoveTimeStart = -1
        }
        if Vector2.Distance(rFootPos, rightHome) > 24 {
            rFootPos = rightHome
            rFootMoveTimeStart = -1
        }
    }


    func UpdateRig() {
        let vector = Vector2(Float(Int(position.x)), Float(Int(position.y)))
        let fromAngleDegrees = Vector2.GetFromAngleDegrees(direction)
        let vector2 = Vector2(0, -1)
        dogRig.underbodyCenter = vector + vector2 * 9
        dogRig.bodyCenter = vector + vector2 * 14
        let num  = Float(Int(SamMath.Lerp(20, 10, dogRig.neckLerpPercent)))
        let num2 = Float(Int(SamMath.Lerp(3, 16, dogRig.neckLerpPercent)))
        dogRig.neckCenter = vector + vector2 * (14 + num)
        dogRig.neckBase = dogRig.bodyCenter + fromAngleDegrees * 15
        dogRig.neckHeadPoint = dogRig.neckBase + fromAngleDegrees * num2 + vector2 * num
        dogRig.head1EndPoint = dogRig.neckHeadPoint + fromAngleDegrees * 3 - vector2 * 1
        dogRig.head2EndPoint = dogRig.head1EndPoint + fromAngleDegrees * 5
    }

    func ToIntPoint(_ vector: Vector2) -> CGPoint {
        CGPoint(x: CGFloat(Int(vector.x)), y: CGFloat(Int(vector.y)))
    }
}

