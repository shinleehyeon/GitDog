// Port of: GooseDesktop/Goose.cs

import Foundation
import CoreGraphics

class Goose {
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

    enum GooseTask: Int {
        case Wander
        case NabMouse
        case CollectWindow_Meme
        case CollectWindow_Notepad
        case CollectWindow_Donate
        case CollectWindow_DONOTSET
        case TrackMud
        case HeartTrail
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
            // Longer, more frequent stops — the dog idles (and sits) more.
            return 2 + SamMath.RandomRange(0, 1) * 4   // 2…6s
        }

        static func GetRandomWanderDuration() -> Float {
            if Time.time < 1 {
                return GooseConfig.settings.FirstWanderTimeSeconds
            }
            return SamMath.RandomRange(GooseConfig.settings.MinWanderingTimeSeconds,
                                       GooseConfig.settings.MaxWanderingTimeSeconds)
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

    var currentSpeed: Float = 80
    var currentAcceleration: Float = 1300
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
    var isResting: Bool = false

    // Speech bubble shown above the dog (e.g. a "커밋해!" nudge). Read by the
    // character view each frame; cleared automatically when it expires.
    private(set) var speechText: String? = nil
    private var speechExpireTime: Float = 0

    private var currentTask: GooseTask = .Wander
    private var taskWanderInfo = Task_Wander()
    private var taskNabMouseInfo = Task_NabMouse()
    private var tmpRect: CGRect = .zero
    private var tmpSize: CGSize = .zero
    private var taskCollectWindowInfo = Task_CollectWindow()
    private var taskTrackMudInfo = Task_TrackMud()
    private var taskHeartTrailInfo = Task_HeartTrail()
    private var nextAllowedNabMouseTime: Float = 0

    // Heavily meme-biased — user wanted the goose to bring memes much more often.
    // CanAttackAtRandom defaults to false, so the NabMouse slots are skipped by
    // ChooseNextTask anyway and effectively re-rolled.
    private var gooseTaskWeightedList: [GooseTask] = [
        .CollectWindow_Meme,
        .CollectWindow_Meme,
        .CollectWindow_Meme,
        .CollectWindow_Meme,
        .CollectWindow_Meme,
        .CollectWindow_Meme,
        .TrackMud,
        .CollectWindow_Notepad
    ]

    private let taskPickerDeck = Deck(8)

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

    var gooseRig = Rig()

    static let ImageUrls: [String] = [
        "https://preview.redd.it/dsfjv8aev0p31.png?width=960&crop=smart&auto=webp&s=1d58948acc5c6dd60df1092c1bd2a59a509069fd",
        "https://i.redd.it/4ojv59zvglp31.jpg",
        "https://i.redd.it/4bamd6lnso241.jpg",
        "https://i.redd.it/5i5et9p1vsp31.jpg",
        "https://i.redd.it/j2f1i9djx5p31.jpg"
    ]

    var ScheduledWanderTime: Float? = nil

    init() {
        position = Vector2(-20, 120)
        targetPos = Vector2(100, 150)
        if !GooseConfig.settings.CanAttackAtRandom {
            let memeOriginalIndex = gooseTaskWeightedList.firstIndex(of: .CollectWindow_Meme) ?? 0
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

    // Show a speech bubble above the dog for `duration` seconds.
    func Say(_ text: String, duration: Float = 4) {
        speechText = text
        speechExpireTime = Time.time + duration
    }

    func Tick() {
        let prevPosition = position
        SetCursorClip(.zero)
        if speechText != nil && Time.time > speechExpireTime {
            speechText = nil
        }
        // Click on the dog toggles resting (sit & stop) instead of grabbing the
        // cursor. Clicking again wakes it back up into normal wandering.
        let clickedOnDog = IsLeftMouseDown() && !lastFrameMouseButtonPressed
            && Vector2.Distance(position + Vector2(0, 14), GetCursorPosition()) < 30
        if clickedOnDog {
            isResting.toggle()
            velocity = .zero
            if isResting {
                targetPos = position
            } else {
                SetTask(.Wander, honck: false)
            }
        }
        lastFrameMouseButtonPressed = IsLeftMouseDown()
        // While resting, freeze in place: no AI, no movement — just keep the rig
        // solved so the sitting pose renders cleanly.
        if isResting {
            velocity = .zero
            targetPos = position
            SolveFeet()
            return
        }
        targetDirection = Vector2.Normalize(targetPos - position)
        overrideExtendNeck = false
        RunAI()
        let vector = Vector2.Lerp(Vector2.GetFromAngleDegrees(direction), targetDirection, 0.25)
        direction = atan2(vector.y, vector.x) * (180 / .pi)
        // During a wander pause, freeze completely. Otherwise the per-frame
        // acceleration toward the (near-but-not-reached) target keeps nudging
        // the position, which reads as a jitter/tremble while "standing still".
        let pausedStill = (currentTask == .Wander && taskWanderInfo.pauseStartTime > 0)
        if pausedStill {
            velocity = .zero
        } else {
            if Vector2.Magnitude(velocity) > currentSpeed {
                velocity = Vector2.Normalize(velocity) * currentSpeed
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
        gooseRig.neckLerpPercent = SamMath.Lerp(gooseRig.neckLerpPercent, num, 0.075)
    }

    func GetMainWindowWidth() -> Float { fatalError("abstract") }
    func GetMainWindowHeight() -> Float { fatalError("abstract") }

    private func RunWander() {
        if Time.time - taskWanderInfo.wanderingStartTime > taskWanderInfo.wanderingDuration {
            ChooseNextTask()
        } else if taskWanderInfo.pauseStartTime > 0 {
            if Time.time - taskWanderInfo.pauseStartTime > taskWanderInfo.pauseDuration {
                taskWanderInfo.pauseStartTime = -1
                // Vary the pace each leg — mostly a slow stroll, sometimes a
                // normal walk. (Slower legs are also shorter → more pausing.)
                SetSpeed(SamMath.RandomRange(0, 1) < 0.5 ? .Stroll : .Walk)
                let num = Task_Wander.GetRandomWalkTime() * currentSpeed
                targetPos = Vector2(SamMath.RandomRange(0, GetMainWindowWidth()),
                                    SamMath.RandomRange(0, GetMainWindowHeight()))
                if Vector2.Distance(position, targetPos) > num {
                    targetPos = position + Vector2.Normalize(targetPos - position) * num
                }
            } else {
                velocity = .zero
            }
        } else if Vector2.Distance(position, targetPos) < 20 {
            taskWanderInfo.pauseStartTime = Time.time
            taskWanderInfo.pauseDuration = Task_Wander.GetRandomPauseDuration()
        }
    }

    func GetCursorPosition() -> Vector2 { fatalError("abstract") }
    func BringWindowToForeground() { fatalError("abstract") }
    func PlaySound(_ sound: SoundEffect) { fatalError("abstract") }

    private func RunNabMouse() {
        let cursorPosition = GetCursorPosition()
        let head2EndPoint = gooseRig.head2EndPoint
        if taskNabMouseInfo.currentStage == .SeekingMouse {
            SetSpeed(.Charge)
            targetPos = cursorPosition - (gooseRig.head2EndPoint - position)
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
            if Vector2.Distance(position, targetPos) < 5 {
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
                let p = gooseRig.head2EndPoint - taskCollectWindowInfo.windowOffsetToBeak
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
                targetPos = heartPoint(progress: 0, center: taskHeartTrailInfo.center,
                                       xScale: taskHeartTrailInfo.xScale, yScale: taskHeartTrailInfo.yScale)
            }
            return
        }
        let elapsed = Time.time - taskHeartTrailInfo.startTime
        if elapsed >= taskHeartTrailInfo.duration {
            SetTask(.Wander, honck: false)
            return
        }
        let p = elapsed / taskHeartTrailInfo.duration
        targetPos = heartPoint(progress: p, center: taskHeartTrailInfo.center,
                               xScale: taskHeartTrailInfo.xScale, yScale: taskHeartTrailInfo.yScale)
    }

    private func ChooseNextTask() {
        if !GooseConfig.settings.CanAttackAtRandom && Time.time < GooseConfig.settings.FirstWanderTimeSeconds + 1 {
            // Keep startup in normal random wander; avoid forced offscreen run.
            SetTask(.Wander, honck: false)
            return
        }
        if allowOccasionalNabMouse && Time.time >= nextAllowedNabMouseTime {
            // Low probability gate + long cooldown so it happens sometimes, not often.
            if SamMath.RandomRange(0, 1) < 0.06 {
                nextAllowedNabMouseTime = Time.time + SamMath.RandomRange(45, 90)
                SetTask(.NabMouse, honck: false)
                return
            }
            // Even when not triggered, push next check out a bit to avoid repeated rolls.
            nextAllowedNabMouseTime = Time.time + 10
        }
        // Prevent hangs: if all weighted tasks are filtered out, fallback to Wander.
        for _ in 0..<(gooseTaskWeightedList.count * 3) {
            let gooseTask = gooseTaskWeightedList[taskPickerDeck.Next()]
            let blockedByAttackSetting = !GooseConfig.settings.CanAttackAtRandom && gooseTask == .NabMouse
            let blockedByCollectSetting = !allowAutomaticCollectWindows && isAutomaticCollectWindowTask(gooseTask)
            let blockedTrackMud = gooseTask == .TrackMud
            if blockedByAttackSetting || blockedByCollectSetting || blockedTrackMud {
                continue
            }
            SetTask(gooseTask)
            return
        }
        SetTask(.Wander, honck: false)
    }

    func CreateImageForm() -> IMovableForm { fatalError("abstract") }
    func CreateTextForm(_ title: String, _ note: String) -> IMovableForm { fatalError("abstract") }
    func CreateDonateForm() -> IMovableForm { fatalError("abstract") }

    func GetNextNote() -> String {
        return Goose.possiblePhrases[Goose.textIndices.Next()]
    }

    func SetTask(_ task: GooseTask, honck: Bool = true) {
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
        case .NabMouse:
            taskNabMouseInfo = Task_NabMouse()
            taskNabMouseInfo.chaseStartTime = Time.time
        case .CollectWindow_Meme:
            taskCollectWindowInfo = Task_CollectWindow()
            taskCollectWindowInfo.mainForm = CreateImageForm()
            SetTask(.CollectWindow_DONOTSET, honck: false)
        case .CollectWindow_Notepad:
            taskCollectWindowInfo = Task_CollectWindow()
            taskCollectWindowInfo.mainForm = CreateTextForm("Goose \"Not-epad\"", GetNextNote())
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
        case .CollectWindow_Meme, .CollectWindow_Notepad, .CollectWindow_Donate, .Count:
            break
        }
    }

    private func isAutomaticCollectWindowTask(_ task: GooseTask) -> Bool {
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
        gooseRig.underbodyCenter = vector + vector2 * 9
        gooseRig.bodyCenter = vector + vector2 * 14
        let num  = Float(Int(SamMath.Lerp(20, 10, gooseRig.neckLerpPercent)))
        let num2 = Float(Int(SamMath.Lerp(3, 16, gooseRig.neckLerpPercent)))
        gooseRig.neckCenter = vector + vector2 * (14 + num)
        gooseRig.neckBase = gooseRig.bodyCenter + fromAngleDegrees * 15
        gooseRig.neckHeadPoint = gooseRig.neckBase + fromAngleDegrees * num2 + vector2 * num
        gooseRig.head1EndPoint = gooseRig.neckHeadPoint + fromAngleDegrees * 3 - vector2 * 1
        gooseRig.head2EndPoint = gooseRig.head1EndPoint + fromAngleDegrees * 5
    }

    func ToIntPoint(_ vector: Vector2) -> CGPoint {
        CGPoint(x: CGFloat(Int(vector.x)), y: CGFloat(Int(vector.y)))
    }
}
