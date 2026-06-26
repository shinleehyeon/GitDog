// Port of: SamEngine/SamMath.cs

import Foundation

public enum SamMath {
    public static let Deg2Rad: Float = .pi / 180
    public static let Rad2Deg: Float = 180 / .pi

    public static var Rand = SystemRandomNumberGenerator()

    public static func RandomRange(_ min: Float, _ max: Float) -> Float {
        if max <= min { return min }
        return Float.random(in: min...max)
    }

    public static func Lerp(_ a: Float, _ b: Float, _ p: Float) -> Float {
        a * (1 - p) + b * p
    }

    public static func Clamp(_ a: Float, _ min: Float, _ max: Float) -> Float {
        Swift.min(Swift.max(a, min), max)
    }
}
