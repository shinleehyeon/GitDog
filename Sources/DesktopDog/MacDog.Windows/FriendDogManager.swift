import Foundation
import AppKit

private final class FriendDog {
    let dog: MacintoshGitDog
    init(_ dog: MacintoshGitDog) { self.dog = dog }
}

final class FriendDogManager {
    static let shared = FriendDogManager()
    private var friends: [FriendDog] = []

    private static let exitLines: [[String]] = [
        ["ㅉㅉ 간다"],
        ["에휴 간다"],
    ]

    private static let wanderLines: [[String]] = [
        ["야 코딩좀\n해라 제발"],
        ["잔디 텅텅\n비어있어 커밋해"],
    ]

    private enum SpawnEdge { case left, right, top }
    private var spawnEdge: SpawnEdge = .left
    private init() {}

    func dismissAll() {
        for f in friends { f.dog.dismiss() }
        friends = []
    }

    // Spawns 2 friend dogs from the same off-screen position as the main dog.
    // `pos` is the main dog's position at the moment it turned back (deep off-screen).
    func spawnFriends(near pos: Vector2, screenWidth w: Float, screenHeight h: Float) {
        dismissAll()

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
            let dog = MacintoshGitDog(memesDirectory: "", notesDirectory: "")
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
            let delay = 1.0 + Double(i) * 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.wanderThenExit(f, wandersRemaining: 1, index: i)
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
        let target = Vector2(tx, ty)
        let dist = Vector2.Distance(f.dog.position, target)
        let halfwayDelay = Double(dist / 2.0 / f.dog.currentSpeed)
        if halfwayDelay >= 1.5 {
            let safeIndex = min(index, Self.wanderLines.count - 1)
            let line = Self.wanderLines[safeIndex].randomElement()!
            DispatchQueue.main.asyncAfter(deadline: .now() + halfwayDelay) { [weak f] in
                f?.dog.Say(line, duration: 3.0)
            }
        }
        f.dog.walkTo(target) { [weak self] in
            let pause = Double.random(in: 0.5...1.2)
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

    // Called each frame by MacintoshGitDog's tick timer.
    func tickAll() {
        for f in friends {
            f.dog.tickAndRedraw()
        }
    }
}
