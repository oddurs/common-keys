import Foundation

/// Which words a run uses. Training and evaluation split dictionary words by a hash of the word, so
/// no word the weights were fitted on is ever used to judge them.
public enum Split: String, Sendable, CaseIterable {
    case all, train, heldOut

    public func contains(_ word: String) -> Bool {
        switch self {
        case .all: true
        case .heldOut: Self.bucket(word) == 0
        case .train: Self.bucket(word) != 0
        }
    }

    /// One word in five is held out. FNV-1a, because Swift's own hashing changes between runs.
    private static func bucket(_ word: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in word.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash % 5
    }
}

/// A labelled example: the evidence that keys typed on one keyboard were meant for another.
public struct Example: Sendable {
    public var evidence: FeatureVector
    public var meant: Bool
}

/// Fits the combiner's weights on examples the engine makes itself: every dictionary word typed on
/// its own keyboard (leave it alone) and on every other keyboard (fix it back).
public enum Training {
    /// Leaving a right word alone matters this much more than fixing a wrong one, so the fitted
    /// boundary sits on the cautious side.
    static let falseFixCost = 20.0

    /// Evidence with no signal in synthetic data: nothing is taught yet, converting methods have no
    /// word lists. These keep their hand weights, scaled to the fitted ones.
    static let fixed: Set<Feature> = [.taught, .readingAccepted, .readingLength, .readingRejected, .unmodeledMethod]

    @MainActor
    public static func examples(
        _ sets: [[any Keyboard]], words count: Int, split: Split, lexicon: SystemLexicon
    ) -> [Example] {
        let detector = Detector()
        var examples: [Example] = []
        for keyboards in sets {
            for meant in keyboards where meant.kind != .converting && lexicon.hasDictionary(meant.baseLanguage) {
                for (word, strokes) in Evaluation.sample(meant, count, lexicon, split: split) {
                    for other in keyboards where other.id != meant.id && other.kind != .converting {
                        guard other.text(for: strokes) != word else { continue }
                        // Typed right: reading it on the other keyboard would be a false fix.
                        examples.append(
                            Example(
                                evidence: detector.evidence(
                                    strokes, typedIn: meant, meantFor: other, memory: Memory(), lexicon: lexicon),
                                meant: false))
                        // Typed on the other keyboard: reading it on this one is the fix.
                        examples.append(
                            Example(
                                evidence: detector.evidence(
                                    strokes, typedIn: other, meantFor: meant, memory: Memory(), lexicon: lexicon),
                                meant: true))
                    }
                }
            }
        }
        return examples
    }

    /// Weighted, L2-regularized logistic regression by Newton's method, then a threshold above every
    /// negative example's score so the weights make no false fix on what they were fitted to.
    public static func fit(_ examples: [Example], l2: Double = 1) -> Weights {
        let active = Feature.allCases.filter { feature in
            !fixed.contains(feature) && examples.contains { $0.evidence[feature] != 0 }
        }
        let d = active.count + 1  // The last coefficient is the bias.
        var beta = [Double](repeating: 0, count: d)
        let rows = examples.map { example in active.map { example.evidence[$0] } + [1] }

        for _ in 0..<30 {
            var gradient = [Double](repeating: 0, count: d)
            var hessian = [[Double]](repeating: [Double](repeating: 0, count: d), count: d)
            for (row, example) in zip(rows, examples) {
                let z = zip(row, beta).reduce(0) { $0 + $1.0 * $1.1 }
                let p = 1 / (1 + exp(-z))
                let weight = example.meant ? 1 : falseFixCost
                let residual = weight * (p - (example.meant ? 1 : 0))
                let curvature = weight * p * (1 - p)
                for i in 0..<d {
                    gradient[i] += residual * row[i]
                    for j in 0..<d { hessian[i][j] += curvature * row[i] * row[j] }
                }
            }
            for i in 0..<(d - 1) {
                gradient[i] += l2 * beta[i]
                hessian[i][i] += l2
            }
            guard let step = solve(hessian, gradient) else { break }
            beta = zip(beta, step).map(-)
            if step.map(abs).max() ?? 0 < 1e-9 { break }
        }

        var values = Dictionary(uniqueKeysWithValues: zip(active, beta))
        let bias = beta[d - 1]
        func score(_ example: Example) -> Double { active.reduce(0) { $0 + values[$1]! * example.evidence[$1] } }
        let highestNegative = examples.filter { !$0.meant }.map(score).max() ?? 0
        // At least even odds, and a quarter logit clear of the closest call that must stay unfixed.
        let threshold = max(-bias, highestNegative + 0.25)
        // Hand weights were set against a threshold of 2; keep their share of it.
        let scale = threshold / Weights.hand.threshold
        for feature in Feature.allCases where values[feature] == nil {
            values[feature] = (Weights.hand.values[feature] ?? 0) * scale
        }
        return Weights(values, threshold: threshold)
    }

    /// Solves `a · x = b` by Gaussian elimination with partial pivoting; nil when singular.
    static func solve(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        var m = zip(a, b).map { $0 + [$1] }
        let n = b.count
        for column in 0..<n {
            guard let pivot = (column..<n).max(by: { abs(m[$0][column]) < abs(m[$1][column]) }),
                abs(m[pivot][column]) > 1e-12
            else { return nil }
            m.swapAt(column, pivot)
            for row in 0..<n where row != column {
                let factor = m[row][column] / m[column][column]
                for k in column...n { m[row][k] -= factor * m[column][k] }
            }
        }
        return (0..<n).map { m[$0][n] / m[$0][$0] }
    }

    /// The weights as Swift source, for checking in where review can read them.
    public static func source(_ weights: Weights, note: String) -> String {
        let lines = Feature.allCases.map { feature in
            "        .\(feature.rawValue): \(format(weights.values[feature] ?? 0)),"
        }
        return """
            // Generated by `worldkey train --write`. Regenerate rather than edit.

            extension Weights {
                /// \(note)
                public static let trained = Weights(
                    [
            \(lines.map { "    " + $0 }.joined(separator: "\n"))
                    ],
                    threshold: \(format(weights.threshold)))
            }

            """
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}
