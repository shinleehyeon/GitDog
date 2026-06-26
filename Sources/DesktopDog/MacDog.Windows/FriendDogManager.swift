import Foundation
import AppKit

private final class FriendDog {
    let dog: MacintoshGoose
    init(_ dog: MacintoshGoose) { self.dog = dog }
}

final class FriendDogManager {
    static let shared = FriendDogManager()
    private var friends: [FriendDog] = []

    private static let exitLines: [[String]] = [
        ["에휴\n가야지 ㅉㅉ", "ㅋㅋ 가자 ㅉㅉ", "나 간다\n잘 있어 ㅉㅉ", "에휴 ㅉㅉ.."],
        ["ㅋㅋ 나도\n가야겠다 ㅉㅉ", "ㅉㅉ", "ㅋ 잘있어 ㅉㅉ", "에휴 참..ㅉㅉ"],
    ]

    private enum SpawnEdge { case left, right, top }
    private var spawnEdge: SpawnEdge = .left
    private init() {}

    // Spawns 2 friend dogs from the same off-screen position as the main dog.
    // `pos` is the main dog's position at the moment it turned back (deep off-screen).
    func spawnFriends(near pos: Vector2, screenWidth w: Float, screenHeight h: Float) {
        for f in friends { f.dog.dismiss() }
        friends = []

        let distL = pos.x
        let distR = w - pos.x
        let distT = pos.y

        let startPositions: [Vector2]
        let targetPositions: [Vector2]
        let inset: Float = 170

        if distT < distL && distT < distR {
            spawnEdge = .top
            startPositions = [
                Vector2(max(60, pos.x - 60), pos.y),
                Vector2(min(w - 60, pos.x + 60), pos.y),
            ]
            targetPositions = [
                Vector2(startPositions[0].x, inset),
                Vector2(startPositions[1].x, inset),
            ]
        } else if distL <= distR {
            spawnEdge = .left
            startPositions = [
                Vector2(pos.x, max(60, pos.y - 60)),
                Vector2(pos.x, min(h - 60, pos.y + 60)),
            ]
            targetPositions = [
                Vector2(inset, startPositions[0].y),
                Vector2(inset, startPositions[1].y),
            ]
        } else {
            spawnEdge = .right
            startPositions = [
                Vector2(pos.x, max(60, pos.y - 60)),
                Vector2(pos.x, min(h - 60, pos.y + 60)),
            ]
            targetPositions = [
                Vector2(w - inset, startPositions[0].y),
                Vector2(w - inset, startPositions[1].y),
            ]
        }

        for i in 0..<2 {
            let dog = MacintoshGoose(memesDirectory: "", notesDirectory: "")
            dog.makeExternallyManaged()
            dog.swapCharacter(to: .chick)
            dog.coatVariant = i + 1
            dog.position = startPositions[i]
            dog.walkTo(targetPositions[i]) {
                dog.velocity = .zero
                dog.targetPos = dog.position       // clear stale dest so toTarget = 0
                dog.lockedTarget = dog.position
                dog.onLockedTargetArrival = nil
                dog.targetDirection = Vector2(0, 1)
            }
            dog.currentSpeed = 80
            friends.append(FriendDog(dog))
        }
    }

    // Called when main dog enters the Chatting stage: brief pause → wander → exit.
    func startDialogue() {
        guard friends.count >= 2 else { return }
        for (i, f) in friends.enumerated() {
            let delay = 2.0 + Double(i) * 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.wanderThenExit(f, wandersRemaining: 3, index: i)
            }
        }
    }

    private func wanderThenExit(_ f: FriendDog, wandersRemaining: Int, index: Int) {
        guard friends.contains(where: { $0 === f }) else { return }
        guard wandersRemaining > 0 else {
            exitFriend(f, index: index)
            return
        }
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let w = Float(screen.width)
        let h = Float(screen.height)
        let margin: Float = 120
        let tx = Float.random(in: margin...(w - margin))
        let ty = Float.random(in: margin...(h - margin))
        f.dog.currentSpeed = 80
        f.dog.walkTo(Vector2(tx, ty)) { [weak self] in
            let pause = Double.random(in: 0.8...2.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
                self?.wanderThenExit(f, wandersRemaining: wandersRemaining - 1, index: index)
            }
        }
    }

    private func exitFriend(_ f: FriendDog, index: Int) {
        guard friends.contains(where: { $0 === f }) else { return }
        let w = friends.first?.dog.GetMainWindowWidth() ?? 1440
        let safeIndex = min(index, Self.exitLines.count - 1)
        let line = Self.exitLines[safeIndex].randomElement()!
        f.dog.Say(line, duration: 2.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self else { return }
            let offTarget: Vector2
            switch self.spawnEdge {
            case .left:  offTarget = Vector2(-90, f.dog.position.y)
            case .right: offTarget = Vector2(w + 90, f.dog.position.y)
            case .top:   offTarget = Vector2(f.dog.position.x, -90)
            }
            f.dog.walkTo(offTarget) { [weak self] in
                f.dog.dismiss()
                self?.friends.removeAll { $0 === f }
            }
            f.dog.currentSpeed = 80
        }
    }

    // Called each frame by MacintoshGoose's tick timer.
    func tickAll() {
        for f in friends {
            f.dog.tickAndRedraw()
        }
    }
}
