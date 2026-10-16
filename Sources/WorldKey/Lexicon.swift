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
    /// when there is no model for it.
    func typicality(_ text: String, on keyboard: any Keyboard) -> Double?
    /// Whether `word` is in the word list shipped for a language macOS has no dictionary for.
    /// A list is far from every word, so only being on it says anything.
    func isListed(_ word: String, language: String) -> Bool
}

extension Lexicon {
    public func startsWord(_ prefix: String, language: String) -> Bool? { nil }
    public func languageLikelihood(_ text: String, among languages: [String]) -> [String: Double] { [:] }
    public func typicality(_ text: String, on keyboard: any Keyboard) -> Double? { nil }
    public func isListed(_ word: String, language: String) -> Bool { false }
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

    public init() {}

    public func isListed(_ word: String, language: String) -> Bool {
        if let list = lists[language] { return list.contains(word.lowercased()) }
        guard let shipped = WordLists.shipped(language) else { return false }
        let list = Set(shipped)
        lists[language] = list
        return list.contains(word.lowercased())
    }

    public func typicality(_ text: String, on keyboard: any Keyboard) -> Double? {
        guard keyboard.kind != .converting else { return nil }
        let language = keyboard.baseLanguage
        if let model = models[language] { return model.typicality(text) }
        guard buildsModelsOnDemand, !modelless.contains(language) else { return nil }
        guard let words = wordList(for: keyboard) else {
            modelless.insert(language)
            return nil
        }
        let model = CharacterModel(words: words.filter(modelSplit.contains))
        models[language] = model
        return model.typicality(text)
    }

    /// The words a language's model learns from: a shipped list where macOS has no dictionary,
    /// else the spell checker's own words, so the model matches this Mac.
    public func wordList(for keyboard: any Keyboard) -> [String]? {
        if let shipped = WordLists.shipped(keyboard.baseLanguage) { return shipped }
        guard hasDictionary(keyboard.baseLanguage) else { return nil }
        var words: Set<String> = []
        for start in keyboard.twoKeyStarts {
            for word in self.words(startingWith: start, language: keyboard.baseLanguage) {
                words.insert(word.lowercased())
            }
        }
        return words.isEmpty ? nil : words.sorted()
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
        } else if hasDictionary(language) {
            for (index, start) in keyboard.twoKeyStarts.enumerated() {
                for word in self.words(startingWith: start, language: language) { words.insert(word.lowercased()) }
                if index % 20 == 19 { await Task.yield() }
            }
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

    public var languagesWithDictionaries: [String] { NSSpellChecker.shared.availableLanguages }

    public func isWord(_ word: String, language: String) -> Bool? {
        guard let dictionary = dictionary(for: language) else { return nil }
        let key = "\(dictionary)\u{0}\(word)"
        if let cached = verdicts[key] { return cached }
        let checker = NSSpellChecker.shared
        let miss = checker.checkSpelling(
            of: word, startingAt: 0, language: dictionary, wrap: false, inSpellDocumentWithTag: 0,
            wordCount: nil)
        // Some dictionaries, Hebrew and Greek among them, pass any string of their letters, and a
        // short string usually starts some real word. A real word is listed among its own completions.
        let valid = miss.location == NSNotFound && listed(word, dictionary)
        if verdicts.count > 4096 { verdicts.removeAll(keepingCapacity: true) }
        verdicts[key] = valid
        return valid
    }

    public func startsWord(_ prefix: String, language: String) -> Bool? {
        guard let dictionary = dictionary(for: language) else { return nil }
        return completions(prefix, dictionary) > 0
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
        return NSSpellChecker.shared.completions(
            forPartialWordRange: NSRange(location: 0, length: (prefix as NSString).length), in: prefix,
            language: dictionary, inSpellDocumentWithTag: 0) ?? []
    }

    public func hasDictionary(_ language: String) -> Bool { dictionary(for: language) != nil }

    private func listed(_ word: String, _ dictionary: String) -> Bool {
        let completions =
            NSSpellChecker.shared.completions(
                forPartialWordRange: NSRange(location: 0, length: (word as NSString).length), in: word,
                language: dictionary, inSpellDocumentWithTag: 0) ?? []
        return completions.contains { $0.compare(word, options: .caseInsensitive) == .orderedSame }
    }

    private func completions(_ prefix: String, _ dictionary: String) -> Int {
        NSSpellChecker.shared.completions(
            forPartialWordRange: NSRange(location: 0, length: (prefix as NSString).length), in: prefix,
            language: dictionary, inSpellDocumentWithTag: 0)?.count ?? 0
    }

    private func dictionary(for language: String) -> String? {
        if let cached = dictionaries[language] { return cached }
        let available = NSSpellChecker.shared.availableLanguages
        let base = String(language.split(separator: "-").first ?? "")
        let match =
            available.first { $0 == language } ?? available.first { $0 == base }
            ?? available.first { $0.hasPrefix(base + "_") }
        dictionaries[language] = match
        return match
    }
}
