// Port of: SamEngine/Deck.cs

import Foundation

final class Deck {
    var indices: [Int]
    private var i: Int = 0

    init(_ Length: Int) {
        indices = Array(repeating: 0, count: Length)
        Reshuffle()
    }

    func Reshuffle() {
        for i in 0..<indices.count {
            indices[i] = i
            let num = Int(SamMath.RandomRange(0, Float(i)))
            let num2 = indices[i]
            indices[i] = indices[num]
            indices[num] = num2
        }
    }

    func Next() -> Int {
        let result = indices[i]
        i += 1
        if i >= indices.count {
            Reshuffle()
            i = 0
        }
        return result
    }
}
