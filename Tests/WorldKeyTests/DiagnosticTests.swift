import AppKit
import Testing

@MainActor
struct DiagnosticTests {
    @Test func spellCheckerOnThisMachine() {
        let checker = NSSpellChecker.shared
        print("DIAG languages:", checker.availableLanguages)
        print(
            "DIAG userPreferred:", checker.userPreferredLanguages, "automatic:",
            checker.automaticallyIdentifiesLanguages)
        for (word, lang) in [
            ("привет", "ru"), ("прив", "ru"), ("hello", "en"), ("שלום", "he"), ("þetta", "is"), ("안녕", "ko"),
        ] {
            let miss = checker.checkSpelling(
                of: word, startingAt: 0, language: lang, wrap: false, inSpellDocumentWithTag: 0,
                wordCount: nil)
            let completions =
                checker.completions(
                    forPartialWordRange: NSRange(location: 0, length: (word as NSString).length), in: word,
                    language: lang, inSpellDocumentWithTag: 0) ?? []
            print("DIAG", lang, word, "miss:", miss.location, "completions:", completions.prefix(8))
        }
    }
}
