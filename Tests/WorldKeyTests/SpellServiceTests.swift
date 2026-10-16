import Foundation
import Testing

@testable import WorldKey

/// A spell checker in a chosen state: which words it knows, whether it completes, and whether it
/// passes any string at all, as some real dictionaries do.
@MainActor
final class FakeSpellService: SpellService {
    var words: Set<String>
    var completes: Bool
    var lenient: Bool
    var languages: [String] { ["ru"] }

    init(words: Set<String>, completes: Bool, lenient: Bool = false) {
        (self.words, self.completes, self.lenient) = (words, completes, lenient)
    }

    func accepts(_ word: String, dictionary: String) -> Bool { lenient || words.contains(word) }

    func completions(_ prefix: String, dictionary: String) -> [String] {
        guard completes else { return [] }
        // A full list for any start, as a working dictionary gives.
        return words.filter { $0.hasPrefix(prefix) } + (0..<20).map { "\(prefix)\($0)" }
    }
}

@MainActor
struct SpellServiceTests {
    let russian: Set<String> = ["привет", "пока", "как"]

    @Test func withCompletionsAWordMustBeListed() {
        let lexicon = SystemLexicon(spelling: FakeSpellService(words: russian, completes: true))
        #expect(lexicon.isWord("привет", language: "ru") == true)
        #expect(lexicon.startsWord("при", language: "ru") == true)
    }

    @Test func withoutCompletionsTheSpellCheckDecides() {
        let lexicon = SystemLexicon(spelling: FakeSpellService(words: russian, completes: false))
        #expect(lexicon.isWord("привет", language: "ru") == true)
        #expect(lexicon.isWord("руддщ", language: "ru") == false)
        #expect(lexicon.startsWord("при", language: "ru") == nil)
    }

    /// A dictionary that passes anything says nothing on its own; without completions it is no
    /// evidence either way, rather than a yes for every string.
    @Test func aLenientDictionaryWithoutCompletionsHasNoOpinion() {
        let lexicon = SystemLexicon(spelling: FakeSpellService(words: russian, completes: false, lenient: true))
        #expect(lexicon.isWord("руддщ", language: "ru") == nil)
    }

    @Test func noWordListIsHarvestedWhileCompletionsAreDown() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "WorldKeyTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let lexicon = SystemLexicon(spelling: FakeSpellService(words: russian, completes: false))
        let keyboard = try #require(InputSources.keyboard("com.apple.keylayout.Russian"))
        #expect(lexicon.wordList(for: keyboard) == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}
