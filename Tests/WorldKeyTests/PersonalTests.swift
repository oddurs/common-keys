import Foundation
import Testing

@testable import WorldKey

@MainActor
struct PersonalTests {
    let us = FakeLayout.us
    let icelandic = FakeLayout.icelandic
    var candidates: [any Keyboard] { [us, icelandic] }

    @Test func aWordCountsAsKeptAfterThreeTimes() {
        var memory = Memory()
        for _ in 0..<2 { memory.noteKept(keys("pat"), on: "us") }
        #expect(!memory.isKept(keys("pat"), on: "us"))
        memory.noteKept(keys("pat"), on: "us")
        #expect(memory.isKept(keys("pat"), on: "us"))
        #expect(!memory.isKept(keys("pat"), on: "is"))
    }

    @Test func keptWordsAreSaltedHashesNotText() throws {
        var mine = Memory()
        var theirs = Memory()
        mine.noteKept(keys("pat"), on: "us")
        theirs.noteKept(keys("pat"), on: "us")
        #expect(mine.kept.keys.first != theirs.kept.keys.first)
        let json = String(decoding: try JSONEncoder().encode(mine), as: UTF8.self)
        #expect(!json.contains("pat"))
    }

    @Test func keptWordsStayBounded() {
        var memory = Memory()
        for i in 0..<(Memory.keptLimit + 10) {
            memory.noteKept([KeyStroke(UInt16(i % 50)), KeyStroke(UInt16(i / 50))], on: "us")
        }
        #expect(memory.kept.count <= Memory.keptLimit)
    }

    /// A word the user writes on Icelandic, typed on U.S., gains exactly the kept-word weight, which is
    /// enough to fix a word that sat just under the threshold.
    @Test func aKeptWordOnTheOtherKeyboardTipsTheCall() throws {
        var memory = Memory()
        let before = try #require(
            Detector(weights: memory.personalized(.trained)).alternatives(
                keys("g;"), typedIn: us, candidates: candidates, memory: memory, lexicon: FakeLexicon()
            )
            .first)
        for _ in 0..<3 { memory.noteKept(keys("g;"), on: icelandic.id) }
        let after = try #require(
            Detector(weights: memory.personalized(.trained)).alternatives(
                keys("g;"), typedIn: us, candidates: candidates, memory: memory, lexicon: FakeLexicon()
            )
            .first)
        let weight = memory.personalized(.trained).values[.meantKept] ?? 0
        #expect(abs(after.gain - before.gain - weight) < 1e-9)
        let justUnder = Detector(threshold: before.gain + 1, weights: memory.personalized(.trained))
        #expect(
            justUnder.decide(keys("g;"), typedIn: us, candidates: candidates, memory: Memory(), lexicon: FakeLexicon())
                == nil)
        #expect(
            justUnder.decide(keys("g;"), typedIn: us, candidates: candidates, memory: memory, lexicon: FakeLexicon())?
                .replacement == "gæ")
    }

    @Test func adjustmentsMoveTowardTheLessonsAndStayClamped() {
        var memory = Memory()
        var evidence = FeatureVector()
        evidence[.knownWord] = 1
        evidence[.symbols] = -1
        // A user who converts relentlessly: every lesson says "fix it".
        let lessons = Array(repeating: (example: Example(evidence: evidence, meant: true), weight: 2.0), count: 500)
        memory.adjust(.trained, toward: lessons)
        let personal = memory.personalized(.trained)
        let base = Memory().personalized(.trained)
        for feature in Feature.allCases {
            let shipped = base.values[feature] ?? 0
            let room = shipped == 0 ? Weights.trained.threshold / 10 : abs(shipped) / 2
            #expect(abs((personal.values[feature] ?? 0) - shipped) <= room + 1e-9, "\(feature)")
        }
        #expect((personal.values[.knownWord] ?? 0) > (Weights.trained.values[.knownWord] ?? 0))
        #expect(personal.threshold == Weights.trained.threshold)
    }

    @Test func adjustmentsSurviveSavingAndLoading() throws {
        var memory = Memory()
        var evidence = FeatureVector()
        evidence[.knownWord] = 1
        memory.adjust(.trained, toward: [(Example(evidence: evidence, meant: true), 1)])
        memory.noteKept(keys("pat"), on: "us")
        let loaded = try JSONDecoder().decode(Memory.self, from: JSONEncoder().encode(memory))
        #expect(loaded == memory)
    }

    /// The plan's replay gate: after five hundred corrections that all push toward fixing, taken from
    /// correctly typed words, the engine still changes no correctly typed word.
    @Test func eagerCorrectionsCannotTeachFalseFixes() {
        let keyboards = ["com.apple.keylayout.US", "com.apple.keylayout.Russian"].compactMap(InputSources.keyboard)
        let negatives = Training.examples([keyboards], words: 60, split: .combiner, lexicon: sharedLexicon)
            .filter { !$0.meant }
        var memory = Memory()
        let lessons = (0..<500).map {
            (example: Example(evidence: negatives[$0 % negatives.count].evidence, meant: true), weight: 1.0)
        }
        memory.adjust(.trained, toward: lessons)
        let report = Evaluation.run(
            keyboards, words: 60, lexicon: sharedLexicon, detector: Detector(weights: memory.personalized(.trained)),
            split: .heldOut)
        for source in report.sources {
            #expect(source.falseFixes == 0, "\(source.keyboard): \(source.examples)")
        }
    }
}
