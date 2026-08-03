// Port of: SamEngine/Time.cs

import Foundation

public enum Time {
    private static let start: TimeInterval = CFAbsoluteTimeGetCurrent()
    public static var time: Float = 0
    // Actual elapsed time since the previous tick, clamped so a late timer
    // firing (main-thread hitch, wake from sleep) doesn't cause a huge
    // integration step — position/velocity math uses this instead of a
    // fixed frame-rate constant so motion stays smooth under timer jitter.
    public static var deltaTime: Float = 0
    private static let maxDeltaTime: Float = 1.0 / 15.0

    public static func TickTime() {
        let now = Float(CFAbsoluteTimeGetCurrent() - start)
        deltaTime = min(now - time, maxDeltaTime)
        time = now
    }
}
