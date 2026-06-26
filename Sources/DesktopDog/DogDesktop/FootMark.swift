// Port of: GooseDesktop/FootMark.cs

import Foundation

struct FootMark {
    static let ShrinkTime: Float = 1
    static let Lifetime: Float = 8.5

    var position: Vector2 = .zero
    var time: Float = 0
    var lifetime: Float = FootMark.Lifetime
    var isHeartTrail: Bool = false
}
