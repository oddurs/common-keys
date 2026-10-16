import Foundation
import Testing

@testable import WorldKey

struct TrainingTests {
    @Test func theSplitIsFixedAndHoldsOutAFifth() {
        let words = (0..<2000).map { "word\($0)" }
        let held = words.filter(Split.heldOut.contains)
        #expect(held.count > 300 && held.count < 500)
        #expect(words.allSatisfy { Split.train.contains($0) != Split.heldOut.contains($0) })
        #expect(Split.heldOut.contains("þetta") == Split.heldOut.contains("ÞETTA"))
    }

    @Test func solvesALinearSystem() throws {
        let x = try #require(Training.solve([[2, 1], [1, 3]], [3, 5]))
        #expect(abs(x[0] - 0.8) < 1e-9 && abs(x[1] - 1.4) < 1e-9)
        #expect(Training.solve([[1, 2], [2, 4]], [1, 2]) == nil)
    }

    /// Two kinds of evidence, one telling: the fit must lean on it and leave every negative unfixed.
    @Test func fitsWeightsThatLeaveNegativesAlone() {
        func example(_ known: Double, _ symbols: Double, _ meant: Bool) -> Example {
            var evidence = FeatureVector()
            evidence[.knownWord] = known
            evidence[.symbols] = symbols
            return Example(evidence: evidence, meant: meant)
        }
        let examples =
            (0..<50).map { example(1, Double($0 % 3), true) } + (0..<50).map { example(-1, Double($0 % 3), false) }
            + [example(0, 1, false)]
        let weights = Training.fit(examples)
        #expect((weights.values[.knownWord] ?? 0) > 0)
        for negative in examples where !negative.meant {
            #expect(weights.score(negative.evidence) < weights.threshold)
        }
        let fixed = examples.filter(\.meant).filter { weights.score($0.evidence) >= weights.threshold }
        #expect(fixed.count == 50)
    }

    @Test func untrainableWeightsKeepTheirShareOfTheThreshold() {
        var evidence = FeatureVector()
        evidence[.knownWord] = 1
        let weights = Training.fit([
            Example(evidence: evidence, meant: true), Example(evidence: FeatureVector(), meant: false),
        ])
        let scale = weights.threshold / Weights.hand.threshold
        #expect(abs((weights.values[.taught] ?? 0) - scale * (Weights.hand.values[.taught] ?? 0)) < 1e-9)
    }

    @Test func writesSourceThatNamesEveryFeature() {
        let source = Training.source(.hand, note: "Test.")
        for feature in Feature.allCases { #expect(source.contains(".\(feature.rawValue):")) }
        #expect(source.contains("threshold: 2.0000"))
    }
}
