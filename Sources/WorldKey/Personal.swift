import Foundation

/// What a user's own corrections teach, on their Mac: words they keep, and nudges to the weights.
extension Memory {
    /// Typed and kept this many times, a word counts as one the user writes on that keyboard.
    static let keptAfter = 3.0
    static let keptLimit = 5000

    public mutating func noteKept(_ strokes: [KeyStroke], on keyboardID: String) {
        kept[keptKey(strokes, keyboardID), default: 0] += 1
        // Halving keeps the list current and bounded: words not typed lately fade out.
        if kept.count > Self.keptLimit {
            kept = kept.mapValues { $0 / 2 }.filter { $0.value >= 0.5 }
        }
    }

    public func isKept(_ strokes: [KeyStroke], on keyboardID: String) -> Bool {
        (kept[keptKey(strokes, keyboardID)] ?? 0) >= Self.keptAfter
    }

    private func keptKey(_ strokes: [KeyStroke], _ keyboardID: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 ^ salt
        for byte in "\(keyboardID)\u{0}\(strokes.signature)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// The shipped weights with the user's adjustments, each held within half its shipped size of
    /// where it shipped: a user can sharpen the weights but not teach them to fix everything.
    public func personalized(_ shipped: Weights) -> Weights {
        var values = shipped.values
        // A word the user keeps counts like a dictionary word does for the hand weights: one and a
        // half thresholds, enough to settle a close call but not to outvote clear evidence.
        values[.shownKept] = -1.5 * shipped.threshold
        values[.meantKept] = 1.5 * shipped.threshold
        for (feature, adjustment) in adjustments {
            let base = values[feature] ?? 0
            values[feature] = Self.clamp(base + adjustment, around: base, threshold: shipped.threshold)
        }
        return Weights(values, threshold: shipped.threshold)
    }

    /// One step of logistic regression per example, pulled back toward the shipped weights. The
    /// threshold never moves, so the bar for acting unasked stays where the gate set it.
    public mutating func adjust(_ shipped: Weights, toward examples: [(example: Example, weight: Double)]) {
        let rate = 0.05
        let pull = 0.01
        for (example, weight) in examples {
            let current = personalized(shipped)
            let z = current.score(example.evidence) - current.threshold
            let error = weight * (1 / (1 + exp(-z)) - (example.meant ? 1 : 0))
            for feature in Feature.allCases {
                let value = example.evidence[feature]
                let adjustment = adjustments[feature] ?? 0
                guard value != 0 || adjustment != 0 else { continue }
                let base = shipped.values[feature] ?? 0
                let next = adjustment - rate * (error * value + pull * adjustment)
                adjustments[feature] = Self.clamp(base + next, around: base, threshold: shipped.threshold) - base
            }
        }
    }

    private static func clamp(_ value: Double, around base: Double, threshold: Double) -> Double {
        // Half the shipped weight either way, or a tenth of the threshold for a weight shipped as zero.
        let room = base == 0 ? threshold / 10 : abs(base) / 2
        return min(max(value, base - room), base + room)
    }
}
