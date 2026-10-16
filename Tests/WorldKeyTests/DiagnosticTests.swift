import AppKit
import Testing
import WorldKey

@MainActor
struct DiagnosticTests {
    @Test func lexiconOnThisMachine() {
        let lexicon = SystemLexicon()
        print("DIAG isWord привет:", lexicon.isWord("привет", language: "ru") as Any)
        print("DIAG startsWord прив:", lexicon.startsWord("прив", language: "ru") as Any)
        print("DIAG isWord hello:", lexicon.isWord("hello", language: "en") as Any)
        print("DIAG isWord ghbdtn:", lexicon.isWord("ghbdtn", language: "en") as Any)
        print("DIAG alphabet ru:", lexicon.alphabet(for: "ru") != nil)
        let russian = InputSources.keyboard("com.apple.keylayout.Russian")!
        print("DIAG russian language:", russian.language, russian.baseLanguage)
        print("DIAG completions привет:", lexicon.words(startingWith: "привет", language: "ru"))
        print("DIAG completions прив:", lexicon.words(startingWith: "прив", language: "ru"))
    }
}
