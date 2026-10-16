import Foundation
import Testing

@testable import WorldKey

@MainActor
struct FeatureTests {
    let lexicon = FakeLexicon()

    func features(_ text: String, _ language: String) -> FeatureVector {
        Scorer.features(text, language: language, lexicon: lexicon)
    }

    @Test func aWrongLayoutReadingShowsItsSymbols() {
        let slash = features("/etta", "en")
        #expect(slash[.symbols] == 1)
        #expect(slash[.unknownWord] == 1)
        #expect(slash[.clean] == 0)
        #expect(Weights.hand.score(slash) == -3)
    }

    @Test func aRealWordScoresAsBefore() {
        let thorn = features("þetta", "is")
        #expect(thorn[.knownWord] == 1)
        #expect(thorn[.clean] == 1)
        #expect(Weights.hand.score(thorn) == 4)
        #expect(Weights.hand.score(features("hello;", "en")) == 3.5)
    }

    @Test func evidenceIsTheDifferenceOfReadings() {
        let detector = Detector()
        let evidence = detector.evidence(
            keys("/etta"), typedIn: FakeLayout.us, meantFor: FakeLayout.icelandic, memory: Memory(), lexicon: lexicon)
        #expect(evidence[.symbols] == -1)
        #expect(evidence[.knownWord] == 1)
        let decision = detector.alternatives(
            keys("/etta"), typedIn: FakeLayout.us, candidates: [FakeLayout.us, FakeLayout.icelandic],
            memory: Memory(), lexicon: lexicon
        ).first
        #expect(decision?.gain == Weights.hand.score(evidence))
    }

    @Test func weightsRoundTripAsReadableJSON() throws {
        let data = try JSONEncoder().encode(Weights.hand)
        #expect(String(decoding: data, as: UTF8.self).contains("\"knownWord\""))
        #expect(try JSONDecoder().decode(Weights.self, from: data) == .hand)
    }
}
