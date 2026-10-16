import Foundation
import Testing

@testable import WorldKey

struct CharacterModelTests {
    let english = CharacterModel(words: [
        "the", "there", "then", "this", "that", "these", "other", "mother", "brother", "together", "weather",
        "hello", "help", "held", "hold", "world", "word", "work", "working", "network", "letter", "better",
    ])

    @Test func wordsShapedLikeTheLanguageScoreAboveNoise() {
        #expect(english.naturalness("whether") > english.naturalness("ghbdtn"))
        #expect(english.naturalness("brothers") > english.naturalness("/etta"))
        #expect(english.naturalness("hello") > 0)
    }

    @Test func typicalityCentresOnTheModelsOwnWords() {
        #expect(abs(english.typicality("together")) < 2)
        #expect(english.typicality("xqzvk") < -2)
    }

    @Test func emptyModelsHaveNoOpinion() {
        let empty = CharacterModel(words: [String]())
        #expect(empty.isEmpty)
        #expect(empty.naturalness("anything") == 0)
    }

    @Test func caseAndCompositionDoNotMatter() {
        #expect(english.naturalness("Hello") == english.naturalness("hello"))
        let composed = CharacterModel(words: ["þetta", "það", "fá"])
        #expect(composed.naturalness("fá") == composed.naturalness("fa\u{301}"))
    }
}

struct WordListTests {
    @Test(arguments: ["th", "ka", "hy"])
    func shippedListsLoad(language: String) throws {
        let words = try #require(WordLists.shipped(language))
        #expect(words.count > 3000)
        #expect(words.allSatisfy { $0.unicodeScalars.count >= 2 && $0 == $0.lowercased() })
    }

    @Test func otherLanguagesHaveNone() {
        #expect(WordLists.shipped("en") == nil)
    }

    @Test func modelAndCombinerWordsNeverOverlapOrMeetTheHeldOut() {
        for word in (0..<3000).map({ "w\($0)" }) {
            let parts = [Split.models, .combiner, .heldOut].filter { $0.contains(word) }
            #expect(parts.count == 1)
            #expect(Split.train.contains(word) == !Split.heldOut.contains(word))
        }
    }
}

@MainActor
struct ListedWordTests {
    @Test func aListedWordIsEvidenceOnlyWhenListed() {
        let lexicon = sharedLexicon
        #expect(lexicon.isListed("იყო", language: "ka"))
        #expect(!lexicon.isListed("ზზზზ", language: "ka"))
        #expect(!lexicon.isListed("hello", language: "en"))
    }
}
