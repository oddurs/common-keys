import AppKit
import NaturalLanguage

@MainActor
public protocol Lexicon {
    /// Whether `word` is a word of `language`, or nil when there is no dictionary for it.
    func isWord(_ word: String, language: String) -> Bool?
    /// Whether some word of `language` starts with `prefix`, or nil when there is no dictionary.
    func startsWord(_ prefix: String, language: String) -> Bool?
    /// The letters `language` is written with, or nil when unknown.
    func alphabet(for language: String) -> CharacterSet?
    /// How likely each reading is in its own language, among `languages`, for readings that share
    /// a script. Empty when there is no opinion.
    func languageLikelihood(_ text: String, among languages: [String]) -> [String: Double]
    /// How typical `text` is of the keyboard's language's words, comparable across languages, or nil
    /// when there is no model for it. `complete` is false for the start of a word still being typed.
    func typicality(_ text: String, on keyboard: any Keyboard, complete: Bool) -> Double?
    /// Whether `word` is in the word list shipped for a language macOS has no dictionary for.
    /// A list is far from every word, so only being on it says anything.
    func isListed(_ word: String, language: String) -> Bool
    /// Whether some word in the shipped list starts with `prefix`.
    func startsListed(_ prefix: String, language: String) -> Bool
}

extension Lexicon {
    public func startsWord(_ prefix: String, language: String) -> Bool? { nil }
    public func languageLikelihood(_ text: String, among languages: [String]) -> [String: Double] { [:] }
    public func typicality(_ text: String, on keyboard: any Keyboard, complete: Bool) -> Double? { nil }
    public func isListed(_ word: String, language: String) -> Bool { false }
    public func startsListed(_ prefix: String, language: String) -> Bool { false }
}

/// The spell checker as the lexicon uses it, so tests can stand in for a Mac in any state.
@MainActor
public protocol SpellService {
    var languages: [String] { get }
    func accepts(_ word: String, dictionary: String) -> Bool
    func completions(_ prefix: String, dictionary: String) -> [String]
}

@MainActor
public struct SystemSpellService: SpellService {
    public init() {}

    public var languages: [String] { NSSpellChecker.shared.availableLanguages }

    public func accepts(_ word: String, dictionary: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(
            of: word, startingAt: 0, language: dictionary, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        ).location == NSNotFound
    }

    public func completions(_ prefix: String, dictionary: String) -> [String] {
        NSSpellChecker.shared.completions(
            forPartialWordRange: NSRange(location: 0, length: (prefix as NSString).length), in: prefix,
            language: dictionary, inSpellDocumentWithTag: 0) ?? []
    }
}

/// The system spell checker, CLDR alphabets and the Natural Language recognizer.
@MainActor
public final class SystemLexicon: Lexicon {
    private var dictionaries: [String: String?] = [:]
    private var alphabets: [String: CharacterSet?] = [:]
    private var verdicts: [String: Bool] = [:]
    private let recognizer = NLLanguageRecognizer()
    private var models: [String: CharacterModel] = [:]
    private var lists: [String: Set<String>] = [:]
    private var listStarts: [String: Set<String>] = [:]
    private var modelless: Set<String> = []

    /// Which words character models learn from. Evaluation keeps the words it judges out of them.
    public var modelSplit: Split = .all {
        didSet {
            models = [:]
            modelless = []
        }
    }
    /// Whether a model is built the first time a language is asked about. Building one lists the
    /// spell checker's words, which takes seconds, so the app turns this off and prepares models
    /// ahead with `prepareModel(for:cache:)`.
    public var buildsModelsOnDemand = true

    private let spelling: any SpellService
    /// Whether each dictionary's completions answer, and when that was last asked. macOS downloads
    /// and drops the data behind them on its own, so a dictionary can spell-check without completing.
    private var completionHealth: [String: (works: Bool, checked: ContinuousClock.Instant)] = [:]
    private var acceptsNonsense: [String: Bool] = [:]
    private var probeAlphabets: [String: [String]] = [:]
    private let clock = ContinuousClock()

    public init(spelling: any SpellService = SystemSpellService()) {
        self.spelling = spelling
    }

    public func isListed(_ word: String, language: String) -> Bool {
        if let list = lists[language] { return list.contains(word.lowercased()) }
        guard let shipped = WordLists.shipped(language) else { return false }
        let list = Set(shipped)
        lists[language] = list
        return list.contains(word.lowercased())
    }

    public func startsListed(_ prefix: String, language: String) -> Bool {
        if let starts = listStarts[language] { return starts.contains(prefix.lowercased()) }
        guard let shipped = WordLists.shipped(language) else { return false }
        // Every start of every listed word up to eight letters: longer starts are rarely typed alone.
        var starts: Set<String> = []
        for word in shipped {
            var start = ""
            for character in word.prefix(8) {
                start.append(character)
                starts.insert(start)
            }
        }
        listStarts[language] = starts
        return starts.contains(prefix.lowercased())
    }

    public func typicality(_ text: String, on keyboard: any Keyboard, complete: Bool) -> Double? {
        guard keyboard.kind != .converting else { return nil }
        let language = keyboard.baseLanguage
        if let model = models[language] { return model.typicality(text, complete: complete) }
        guard buildsModelsOnDemand, !modelless.contains(language) else { return nil }
        guard let words = wordList(for: keyboard) else {
            modelless.insert(language)
            return nil
        }
        let model = CharacterModel(words: words.filter(modelSplit.contains))
        models[language] = model
        return model.typicality(text, complete: complete)
    }

    /// The words a language's model learns from: a shipped list where macOS has no dictionary,
    /// else the spell checker's own words, so the model matches this Mac.
    public func wordList(for keyboard: any Keyboard) -> [String]? {
        if let shipped = WordLists.shipped(keyboard.baseLanguage) { return shipped }
        // A list harvested while completions are down would be a handful of stray names.
        guard let dictionary = dictionary(for: keyboard.baseLanguage),
            completionsWork(dictionary, language: keyboard.baseLanguage)
        else { return nil }
        var harvest = Harvest(started: clock.now)
        gather(keyboard.twoKeyStarts, dictionary, into: &harvest)
        guard !harvest.failed else {
            completionHealth[dictionary] = (false, clock.now)
            return nil
        }
        return harvest.words.isEmpty ? nil : harvest.words.sorted()
    }

    /// A language's words, gathered start by start from completions.
    private struct Harvest {
        var words: Set<String> = []
        let started: ContinuousClock.Instant
        /// The spell service answered too slowly to finish without holding up whoever waits.
        var failed = false
    }

    /// A healthy spell service completes a start in about ten milliseconds and a whole language in
    /// a few seconds. Slower than this, harvesting stops and completions count as down until the
    /// next check: a model is a refinement, not worth a stalled Mac.
    static let harvestCallBudget = Duration.milliseconds(250)
    static let harvestBudget = Duration.seconds(30)

    private func gather(_ starts: some Sequence<String>, _ dictionary: String, into harvest: inout Harvest) {
        for start in starts where !harvest.failed {
            let asked = clock.now
            for word in spelling.completions(start, dictionary: dictionary) { harvest.words.insert(word.lowercased()) }
            if clock.now - asked > Self.harvestCallBudget || clock.now - harvest.started > Self.harvestBudget {
                harvest.failed = true
            }
        }
    }

    /// Builds a keyboard's model without holding up typing: the word list comes from the cache when
    /// it was made on this version of macOS, else from the spell checker a few starts at a time.
    /// Throws only when the cache cannot be written; the model is in use by then regardless.
    public func prepareModel(for keyboard: any Keyboard, cache folder: URL) async throws {
        let language = keyboard.baseLanguage
        guard keyboard.kind != .converting, models[language] == nil, !modelless.contains(language) else { return }
        let file = folder.appending(path: "\(language).txt")
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        if let cached = try? String(contentsOf: file, encoding: .utf8) {
            var lines = cached.split(separator: "\n").map(String.init)
            if lines.first == system {
                lines.removeFirst()
                models[language] = CharacterModel(words: lines)
                return
            }
        }
        var words: Set<String> = []
        if let shipped = WordLists.shipped(language) {
            words = Set(shipped)
        } else if let dictionary = dictionary(for: language), completionsWork(dictionary, language: language) {
            var harvest = Harvest(started: clock.now)
            let starts = keyboard.twoKeyStarts
            for chunk in stride(from: 0, to: starts.count, by: 20) where !harvest.failed {
                gather(starts[chunk..<min(chunk + 20, starts.count)], dictionary, into: &harvest)
                await Task.yield()
            }
            // Too slow today: no model, and none cached, so the next launch tries again.
            guard !harvest.failed else {
                completionHealth[dictionary] = (false, clock.now)
                return
            }
            words = harvest.words
        }
        guard !words.isEmpty else {
            modelless.insert(language)
            return
        }
        models[language] = CharacterModel(words: Array(words))
        guard WordLists.shipped(language) == nil else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ([system] + words.sorted()).joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    public var languagesWithDictionaries: [String] { spelling.languages }

    public func isWord(_ word: String, language: String) -> Bool? {
        guard let dictionary = dictionary(for: language) else { return nil }
        let completing = completionsWork(dictionary, language: language)
        let key = "\(dictionary)\u{0}\(completing)\u{0}\(word)"
        if let cached = verdicts[key] { return cached }
        let verdict: Bool?
        if completing {
            // Some dictionaries, Hebrew and Greek among them, pass any string of their letters, and a
            // short string usually starts some real word. A real word is listed among its own completions.
            verdict = spelling.accepts(word, dictionary: dictionary) && listed(word, dictionary)
        } else if dictionaryAcceptsNonsense(dictionary, language: language) {
            // Without completions there is no telling a lenient dictionary's yes from a real word.
            verdict = nil
        } else {
            verdict = spelling.accepts(word, dictionary: dictionary)
        }
        if verdicts.count > 4096 { verdicts.removeAll(keepingCapacity: true) }
        verdicts[key] = verdict
        return verdict
    }

    public func startsWord(_ prefix: String, language: String) -> Bool? {
        guard let dictionary = dictionary(for: language), completionsWork(dictionary, language: language) else {
            return nil
        }
        return completions(prefix, dictionary) > 0
    }

    /// Asks whether the keyboard's dictionary completes words, so the answer is ready before the
    /// first word typed in it: a probe makes up to 64 spell-checker calls.
    public func checkSpelling(for keyboard: any Keyboard) {
        guard keyboard.kind != .converting, let dictionary = dictionary(for: keyboard.baseLanguage) else { return }
        _ = completionsWork(dictionary, language: keyboard.baseLanguage)
    }

    /// Whether `dictionary` completes words right now. A working one returns a full list for many
    /// two-letter starts across its alphabet; with its data gone it returns nothing, or a few stray
    /// English names that start the same way. Asked again every few minutes, in the background,
    /// since macOS may bring the data back.
    func completionsWork(_ dictionary: String, language: String) -> Bool {
        if let health = completionHealth[dictionary] {
            if clock.now - health.checked > .seconds(300) {
                completionHealth[dictionary] = (health.works, clock.now)
                Task { [weak self] in self?.probeCompletions(dictionary, language: language) }
            }
            return health.works
        }
        return probeCompletions(dictionary, language: language)
    }

    /// How long a probe may take. A spell service under load can take seconds to answer each
    /// call, and the probe can run on the main thread, so past this it gives up and reports no
    /// completions: the safe answer, which falls back to the spell check alone.
    static let probeBudget = Duration.milliseconds(500)

    @discardableResult
    private func probeCompletions(_ dictionary: String, language: String) -> Bool {
        let letters = probeLetters(language)
        // Hangul letters are whole syllables, and two-syllable starts are rare, so one does.
        let syllabic =
            letters.first.flatMap { $0.unicodeScalars.first }.map { (0xAC00...0xD7A3).contains($0.value) } ?? false
        let starts = syllabic ? letters : letters.flatMap { first in letters.map { first + $0 } }
        let start = clock.now
        var full = 0
        var works = false
        for prefix in starts {
            if spelling.completions(prefix, dictionary: dictionary).count >= 10 { full += 1 }
            if full >= 3 {
                works = true
                break
            }
            if clock.now - start > Self.probeBudget { break }
        }
        completionHealth[dictionary] = (works, clock.now)
        return works
    }

    /// Whether `dictionary` passes a string no language writes, made of its own letters.
    private func dictionaryAcceptsNonsense(_ dictionary: String, language: String) -> Bool {
        if let known = acceptsNonsense[dictionary] { return known }
        let letters = probeLetters(language)
        guard letters.count >= 2 else { return true }
        let nonsense = String(repeating: letters[0], count: 4) + String(repeating: letters[1], count: 3)
        let accepts = spelling.accepts(nonsense, dictionary: dictionary)
        acceptsNonsense[dictionary] = accepts
        return accepts
    }

    /// Eight letters spread across the language's alphabet, as starts to probe completions with.
    /// Spread rather than the first few, which in some alphabets are rare, like Arabic's hamza forms.
    private func probeLetters(_ language: String) -> [String] {
        if let known = probeAlphabets[language] { return known }
        let letters = spreadLetters(language)
        probeAlphabets[language] = letters
        return letters
    }

    private func spreadLetters(_ language: String) -> [String] {
        guard let alphabet = alphabet(for: language) else { return [] }
        var letters: [String] = []
        for value in UInt32(0x41)...0xD7A3 {
            guard let scalar = Unicode.Scalar(value), alphabet.contains(scalar),
                scalar.properties.isLowercase
                    || !scalar.properties.changesWhenLowercased && scalar.properties.isAlphabetic
            else { continue }
            letters.append(String(scalar))
        }
        guard letters.count > 8 else { return letters }
        return (0..<8).map { letters[$0 * (letters.count - 1) / 7] }
    }

    public func alphabet(for language: String) -> CharacterSet? {
        if let cached = alphabets[language] { return cached }
        let set = NSLocale(localeIdentifier: language).object(forKey: .exemplarCharacterSet) as? CharacterSet
        alphabets[language] = set
        return set
    }

    public func languageLikelihood(_ text: String, among languages: [String]) -> [String: Double] {
        recognizer.reset()
        recognizer.languageConstraints = languages.map(NLLanguage.init(rawValue:))
        recognizer.processString(text)
        return Dictionary(
            uniqueKeysWithValues: recognizer.languageHypotheses(withMaximum: languages.count).map {
                ($0.key.rawValue, $0.value)
            })
    }

    /// Words of `language` that start with `prefix`, from the spell checker's own list.
    public func words(startingWith prefix: String, language: String) -> [String] {
        guard let dictionary = dictionary(for: language) else { return [] }
        return spelling.completions(prefix, dictionary: dictionary)
    }

    public func hasDictionary(_ language: String) -> Bool { dictionary(for: language) != nil }

    private func listed(_ word: String, _ dictionary: String) -> Bool {
        spelling.completions(word, dictionary: dictionary).contains {
            $0.compare(word, options: .caseInsensitive) == .orderedSame
        }
    }

    private func completions(_ prefix: String, _ dictionary: String) -> Int {
        spelling.completions(prefix, dictionary: dictionary).count
    }

    private func dictionary(for language: String) -> String? {
        if let cached = dictionaries[language] { return cached }
        let available = spelling.languages
        let base = String(language.split(separator: "-").first ?? "")
        let match =
            available.first { $0 == language } ?? available.first { $0 == base }
            ?? available.first { $0.hasPrefix(base + "_") }
        dictionaries[language] = match
        return match
    }
}
