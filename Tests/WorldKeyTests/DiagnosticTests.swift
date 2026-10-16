import AppKit
import Testing
import WorldKey

@MainActor
struct DiagnosticTests {
    @Test func detectorOnThisMachine() {
        let lexicon = SystemLexicon()
        let us = InputSources.keyboard("com.apple.keylayout.US")!
        let russian = InputSources.keyboard("com.apple.keylayout.Russian")!
        print(
            "DIAG us:", us.language, us.baseLanguage, us.kind, "ru:", russian.language, russian.baseLanguage)
        print("DIAG us text:", us.text(for: keys("ghbdtn")), "ru text:", russian.text(for: keys("ghbdtn")))
        print("DIAG isWord ghbdtn us.language:", lexicon.isWord("ghbdtn", language: us.language) as Any)
        print("DIAG startsWord ghbd us.language:", lexicon.startsWord("ghbd", language: us.language) as Any)
        print(
            "DIAG hasDictionary us:", lexicon.hasDictionary(us.language),
            lexicon.hasDictionary(us.baseLanguage))
        let alts = Detector().alternatives(
            keys("ghbdtn"), typedIn: us, candidates: [us, russian], memory: Memory(), lexicon: lexicon)
        print("DIAG alternatives:", alts)
        print("DIAG Locale:", Locale.preferredLanguages, Locale.current.identifier)
    }
}
