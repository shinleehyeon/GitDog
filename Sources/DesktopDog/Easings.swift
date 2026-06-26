// Port of: Easings.cs

import Foundation

public enum Easings {
    public enum Functions {
        case Linear
        case QuadraticEaseIn
        case QuadraticEaseOut
        case QuadraticEaseInOut
        case CubicEaseIn
        case CubicEaseOut
        case CubicEaseInOut
        case QuarticEaseIn
        case QuarticEaseOut
        case QuarticEaseInOut
        case QuinticEaseIn
        case QuinticEaseOut
        case QuinticEaseInOut
        case SineEaseIn
        case SineEaseOut
        case SineEaseInOut
        case CircularEaseIn
        case CircularEaseOut
        case CircularEaseInOut
        case ExponentialEaseIn
        case ExponentialEaseOut
        case ExponentialEaseInOut
        case ElasticEaseIn
        case ElasticEaseOut
        case ElasticEaseInOut
        case BackEaseIn
        case BackEaseOut
        case BackEaseInOut
        case BounceEaseIn
        case BounceEaseOut
        case BounceEaseInOut
    }

    private static let PI: Float = .pi
    private static let HALFPI: Float = .pi / 2

    public static func Interpolate(_ p: Float, _ function: Functions) -> Float {
        switch function {
        case .QuadraticEaseIn:       return QuadraticEaseIn(p)
        case .QuadraticEaseOut:      return QuadraticEaseOut(p)
        case .QuadraticEaseInOut:    return QuadraticEaseInOut(p)
        case .CubicEaseIn:           return CubicEaseIn(p)
        case .CubicEaseOut:          return CubicEaseOut(p)
        case .CubicEaseInOut:        return CubicEaseInOut(p)
        case .QuarticEaseIn:         return QuarticEaseIn(p)
        case .QuarticEaseOut:        return QuarticEaseOut(p)
        case .QuarticEaseInOut:      return QuarticEaseInOut(p)
        case .QuinticEaseIn:         return QuinticEaseIn(p)
        case .QuinticEaseOut:        return QuinticEaseOut(p)
        case .QuinticEaseInOut:      return QuinticEaseInOut(p)
        case .SineEaseIn:            return SineEaseIn(p)
        case .SineEaseOut:           return SineEaseOut(p)
        case .SineEaseInOut:         return SineEaseInOut(p)
        case .CircularEaseIn:        return CircularEaseIn(p)
        case .CircularEaseOut:       return CircularEaseOut(p)
        case .CircularEaseInOut:     return CircularEaseInOut(p)
        case .ExponentialEaseIn:     return ExponentialEaseIn(p)
        case .ExponentialEaseOut:    return ExponentialEaseOut(p)
        case .ExponentialEaseInOut:  return ExponentialEaseInOut(p)
        case .ElasticEaseIn:         return ElasticEaseIn(p)
        case .ElasticEaseOut:        return ElasticEaseOut(p)
        case .ElasticEaseInOut:      return ElasticEaseInOut(p)
        case .BackEaseIn:            return BackEaseIn(p)
        case .BackEaseOut:           return BackEaseOut(p)
        case .BackEaseInOut:         return BackEaseInOut(p)
        case .BounceEaseIn:          return BounceEaseIn(p)
        case .BounceEaseOut:         return BounceEaseOut(p)
        case .BounceEaseInOut:       return BounceEaseInOut(p)
        case .Linear:                return Linear(p)
        }
    }

    public static func Linear(_ p: Float) -> Float { p }

    public static func QuadraticEaseIn(_ p: Float) -> Float { p * p }

    public static func QuadraticEaseOut(_ p: Float) -> Float { 0 - p * (p - 2) }

    public static func QuadraticEaseInOut(_ p: Float) -> Float {
        if p < 0.5 { return 2 * p * p }
        return -2 * p * p + 4 * p - 1
    }

    public static func CubicEaseIn(_ p: Float) -> Float { p * p * p }

    public static func CubicEaseOut(_ p: Float) -> Float {
        let num = p - 1
        return num * num * num + 1
    }

    public static func CubicEaseInOut(_ p: Float) -> Float {
        if p < 0.5 { return 4 * p * p * p }
        let num = 2 * p - 2
        return 0.5 * num * num * num + 1
    }

    public static func QuarticEaseIn(_ p: Float) -> Float { p * p * p * p }

    public static func QuarticEaseOut(_ p: Float) -> Float {
        let num = p - 1
        return num * num * num * (1 - p) + 1
    }

    public static func QuarticEaseInOut(_ p: Float) -> Float {
        if p < 0.5 { return 8 * p * p * p * p }
        let num = p - 1
        return -8 * num * num * num * num + 1
    }

    public static func QuinticEaseIn(_ p: Float) -> Float { p * p * p * p * p }

    public static func QuinticEaseOut(_ p: Float) -> Float {
        let num = p - 1
        return num * num * num * num * num + 1
    }

    public static func QuinticEaseInOut(_ p: Float) -> Float {
        if p < 0.5 { return 16 * p * p * p * p * p }
        let num = 2 * p - 2
        return 0.5 * num * num * num * num * num + 1
    }

    public static func SineEaseIn(_ p: Float) -> Float { sin((p - 1) * (.pi / 2)) + 1 }

    public static func SineEaseOut(_ p: Float) -> Float { sin(p * (.pi / 2)) }

    public static func SineEaseInOut(_ p: Float) -> Float { 0.5 * (1 - cos(p * .pi)) }

    public static func CircularEaseIn(_ p: Float) -> Float { 1 - sqrt(1 - p * p) }

    public static func CircularEaseOut(_ p: Float) -> Float { sqrt((2 - p) * p) }

    public static func CircularEaseInOut(_ p: Float) -> Float {
        if p < 0.5 { return 0.5 * (1 - sqrt(1 - 4 * (p * p))) }
        return 0.5 * (sqrt(-(2 * p - 3) * (2 * p - 1)) + 1)
    }

    public static func ExponentialEaseIn(_ p: Float) -> Float {
        if p != 0 { return pow(2, 10 * (p - 1)) }
        return p
    }

    public static func ExponentialEaseOut(_ p: Float) -> Float {
        if p != 1 { return 1 - pow(2, -10 * p) }
        return p
    }

    public static func ExponentialEaseInOut(_ p: Float) -> Float {
        if p == 0 || p == 1 { return p }
        if p < 0.5 { return 0.5 * pow(2, 20 * p - 10) }
        return -0.5 * pow(2, -20 * p + 10) + 1
    }

    public static func ElasticEaseIn(_ p: Float) -> Float {
        sin(20.420353 * p) * pow(2, 10 * (p - 1))
    }

    public static func ElasticEaseOut(_ p: Float) -> Float {
        sin(-20.420353 * (p + 1)) * pow(2, -10 * p) + 1
    }

    public static func ElasticEaseInOut(_ p: Float) -> Float {
        if p < 0.5 {
            return 0.5 * sin(20.420353 * (2 * p)) * pow(2, 10 * (2 * p - 1))
        }
        return 0.5 * (sin(-20.420353 * (2 * p - 1 + 1)) * pow(2, -10 * (2 * p - 1)) + 2)
    }

    public static func BackEaseIn(_ p: Float) -> Float {
        p * p * p - p * sin(p * .pi)
    }

    public static func BackEaseOut(_ p: Float) -> Float {
        let num = 1 - p
        return 1 - (num * num * num - num * sin(num * .pi))
    }

    public static func BackEaseInOut(_ p: Float) -> Float {
        if p < 0.5 {
            let num: Float = 2 * p
            return 0.5 * (num * num * num - num * sin(num * .pi))
        }
        let num2: Float = 1 - (2 * p - 1)
        return 0.5 * (1 - (num2 * num2 * num2 - num2 * sin(num2 * .pi))) + 0.5
    }

    public static func BounceEaseIn(_ p: Float) -> Float { 1 - BounceEaseOut(1 - p) }

    public static func BounceEaseOut(_ p: Float) -> Float {
        if p < 0.36363637 { return 121 * p * p / 16 }
        if p < 0.72727275 { return 9.075 * p * p - 9.9 * p + 3.4 }
        if p < 0.9         { return 12.066482 * p * p - 19.635458 * p + 8.898061 }
        return 10.8 * p * p - 20.52 * p + 10.72
    }

    public static func BounceEaseInOut(_ p: Float) -> Float {
        if p < 0.5 { return 0.5 * BounceEaseIn(p * 2) }
        return 0.5 * BounceEaseOut(p * 2 - 1) + 0.5
    }
}
