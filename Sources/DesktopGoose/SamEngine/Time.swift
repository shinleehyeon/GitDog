// Port of: SamEngine/Time.cs

import Foundation

public enum Time {
    private static let start: TimeInterval = CFAbsoluteTimeGetCurrent()
    public static var time: Float = 0

    public static func TickTime() {
        time = Float(CFAbsoluteTimeGetCurrent() - start)
    }
}
