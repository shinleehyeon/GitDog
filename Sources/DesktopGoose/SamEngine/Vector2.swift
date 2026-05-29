// Port of: SamEngine/Vector2.cs

import Foundation
import CoreGraphics

public struct Vector2 {
    public var x: Float
    public var y: Float

    public static let zero = Vector2(0, 0)

    public init(_ _x: Float, _ _y: Float) {
        x = _x
        y = _y
    }

    public init(cg _x: CGFloat, _ _y: CGFloat) {
        x = Float(_x)
        y = Float(_y)
    }

    public var description: String {
        String(format: "(%g, %g)", x, y)
    }

    public static func + (a: Vector2, b: Vector2) -> Vector2 {
        Vector2(a.x + b.x, a.y + b.y)
    }

    public static func - (a: Vector2, b: Vector2) -> Vector2 {
        Vector2(a.x - b.x, a.y - b.y)
    }

    public static prefix func - (a: Vector2) -> Vector2 {
        a * -1
    }

    public static func * (a: Vector2, b: Vector2) -> Vector2 {
        Vector2(a.x * b.x, a.y * b.y)
    }

    public static func * (a: Vector2, b: Float) -> Vector2 {
        Vector2(a.x * b, a.y * b)
    }

    public static func / (a: Vector2, b: Float) -> Vector2 {
        Vector2(a.x / b, a.y / b)
    }

    public static func += (a: inout Vector2, b: Vector2) {
        a = a + b
    }

    public static func -= (a: inout Vector2, b: Vector2) {
        a = a - b
    }

    public static func GetFromAngleDegrees(_ angle: Float) -> Vector2 {
        Vector2(cos(angle * (Float.pi / 180)),
                sin(angle * (Float.pi / 180)))
    }

    public static func Distance(_ a: Vector2, _ b: Vector2) -> Float {
        let v = Vector2(a.x - b.x, a.y - b.y)
        return sqrt(v.x * v.x + v.y * v.y)
    }

    public static func Lerp(_ a: Vector2, _ b: Vector2, _ p: Float) -> Vector2 {
        Vector2(SamMath.Lerp(a.x, b.x, p), SamMath.Lerp(a.y, b.y, p))
    }

    public static func Dot(_ a: Vector2, _ b: Vector2) -> Float {
        a.x * b.x + a.y * b.y
    }

    public static func Normalize(_ a: Vector2) -> Vector2 {
        if a.x == 0 && a.y == 0 { return .zero }
        let n = sqrt(a.x * a.x + a.y * a.y)
        return Vector2(a.x / n, a.y / n)
    }

    public static func Magnitude(_ a: Vector2) -> Float {
        sqrt(a.x * a.x + a.y * a.y)
    }
}
