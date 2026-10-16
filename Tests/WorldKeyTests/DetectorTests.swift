import Foundation
import Testing

@testable import WorldKey

@MainActor
struct DetectorTests {
    let us = FakeLayout.us
    let icelandic = FakeLayout.icelandic
    let lexicon = FakeLexicon()
    var candidates: [any Keyboard] { [us, icelandic] }

    func decide(_ typed: String, in layout: any Keyboard, memory: Memory = Memory()) -> Decision? {
        Detector().decide(
            keys(typed), typedIn: layout, candidates: candidates, memory: memory, lexicon: lexicon)
    }

    @Test func icelandicTypedOnUSIsFixed() {
        let decision = decide("/etta", in: us)
        #expect(decision?.targetID == "is")
        #expect(decision?.original == "/etta")
        #expect(decision?.replacement == "þetta")
    }

    @Test func englishTypedOnIcelandicIsFixed() {
        let decision = decide("don't", in: icelandic)
        #expect(decision?.original == "don´t")
        #expect(decision?.replacement == "don't")
    }

    @Test func validWordIsLeftAlone() {
        #expect(decide("don't", in: us) == nil)
        #expect(decide("/a[", in: icelandic) == nil)
    }

    @Test func identicalReadingsAreNeverConverted() {
        #expect(decide("hello", in: icelandic) == nil)
    }

    @Test func trailingPunctuationDoesNotTipTheScale() {
        #expect(decide("hello;", in: us) == nil)
    }

    @Test func pathsAreNotWords() {
        #expect(decide("/usr/local", in: us) == nil)
    }

    @Test func shortWordsAreIgnored() {
        #expect(
            Detector(minLength: 3).decide(
                keys("/a"), typedIn: us, candidates: candidates, memory: Memory(), lexicon: lexicon) == nil)
    }

    @Test func learnedWordWinsWithoutEvidence() {
        // "g;" reads as well as "gæ", so scoring alone leaves it.
        #expect(decide("g;", in: us) == nil)
        var memory = Memory()
        memory.learn(keys("g;"), from: us, to: icelandic)
        let decision = decide("g;", in: us, memory: memory)
        #expect(decision?.replacement == "gæ")
        #expect(decision?.learned == true)
    }

    @Test func exceptionBlocksAFix() {
        var memory = Memory()
        memory.keep(keys("/etta"), in: us.id)
        #expect(decide("/etta", in: us, memory: memory) == nil)
    }

    @Test func alternativesRankWithoutThreshold() {
        let ranked = Detector().alternatives(
            keys("g;"), typedIn: us, candidates: candidates, memory: Memory(), lexicon: lexicon)
        #expect(ranked.map(\.replacement) == ["gæ"])
    }
}

@MainActor
struct MemoryTests {
    @Test func learningCountsOnlyKeysThatDiffer() {
        var memory = Memory()
        memory.learn(keys("/etta"), from: FakeLayout.us, to: FakeLayout.icelandic)
        memory.learn(keys("/a["), from: FakeLayout.us, to: FakeLayout.icelandic)
        let counts = Dictionary(uniqueKeysWithValues: memory.confusions.map { ($0.keyCode, $0.count) })
        #expect(counts == [44: 2, 33: 1])
    }

    @Test func boostIsCapped() {
        var memory = Memory()
        for _ in 0..<20 { memory.learn(keys("/[;'"), from: FakeLayout.us, to: FakeLayout.icelandic) }
        #expect(memory.boost(keys("/[;'"), from: "us", to: "is") == 1.5)
        #expect(memory.boost(keys("/[;'"), from: "is", to: "us") == 0)
    }

    @Test func keepingReplacesALearnedWord() {
        var memory = Memory()
        memory.learn(keys("b;"), from: FakeLayout.us, to: FakeLayout.icelandic)
        memory.keep(keys("b;"), in: "us")
        #expect(memory.words.isEmpty)
        #expect(memory.exceptions[keys("b;").signature]?.layoutID == "us")
    }

    @Test func unlearnCountsDown() {
        var memory = Memory()
        memory.learn(keys("b;"), from: FakeLayout.us, to: FakeLayout.icelandic)
        memory.learn(keys("b;"), from: FakeLayout.us, to: FakeLayout.icelandic)
        memory.unlearn(keys("b;"))
        #expect(memory.words.first?.value.count == 1)
        memory.unlearn(keys("b;"))
        #expect(memory.words.isEmpty)
    }

    @Test func survivesARoundTrip() throws {
        var memory = Memory()
        memory.learn(keys("/etta"), from: FakeLayout.us, to: FakeLayout.icelandic)
        memory.keep(keys("pat"), in: "is")
        let data = try JSONEncoder().encode(memory)
        #expect(try JSONDecoder().decode(Memory.self, from: data) == memory)
    }
}

@MainActor
struct AppLanguageTests {
    let candidates: [any Keyboard] = [FakeLayout.us, FakeLayout.icelandic]

    @Test func readingTellsLanguageEvenWhenLayoutsAgree() {
        let detector = Detector()
        #expect(
            detector.clearestReading(keys("hello"), candidates: candidates, lexicon: FakeLexicon()) == "us")
        #expect(
            detector.clearestReading(keys("/etta"), candidates: candidates, lexicon: FakeLexicon()) == "is")
        // A word of both languages says nothing.
        #expect(detector.clearestReading(keys("test"), candidates: candidates, lexicon: FakeLexicon()) == nil)
    }

    @Test func usualLayoutNeedsEnoughTyping() {
        var memory = Memory()
        for _ in 0..<7 { memory.recordUse(app: "mail", layoutID: "is") }
        #expect(memory.usualLayout(app: "mail") == nil)
        memory.recordUse(app: "mail", layoutID: "is")
        #expect(memory.usualLayout(app: "mail")?.id == "is")
    }

    @Test func mixedAppsHaveNoUsualLayout() {
        var memory = Memory()
        for _ in 0..<10 {
            memory.recordUse(app: "slack", layoutID: "is")
            memory.recordUse(app: "slack", layoutID: "us")
        }
        #expect(memory.usualLayout(app: "slack") == nil)
    }

    @Test func recentHabitsWin() {
        var memory = Memory()
        for _ in 0..<300 { memory.recordUse(app: "mail", layoutID: "us") }
        for _ in 0..<300 { memory.recordUse(app: "mail", layoutID: "is") }
        #expect(memory.usualLayout(app: "mail")?.id == "is")
    }

    @Test func olderMemoryStillLoads() throws {
        let json = Data(#"{"words":{},"exceptions":{},"confusions":[]}"#.utf8)
        #expect(try JSONDecoder().decode(Memory.self, from: json).apps.isEmpty)
    }
}

struct FlagTests {
    @Test func flagsComeFromTheLayoutsCountry() {
        #expect(FakeLayout.icelandic.flag == "🇮🇸")
        #expect(FakeLayout.us.flag == "🇺🇸")
        let british = FakeLayout(
            id: "com.apple.keylayout.British-PC", name: "British", language: "en", table: [:])
        #expect(british.flag == "🇬🇧")
    }
}
