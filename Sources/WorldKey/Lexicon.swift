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
}

extension Lexicon {
    public func startsWord(_ prefix: String, language: String) -> Bool? { nil }
    public func languageLikelihood(_ text: String, among languages: [String]) -> [String: Double] { [:] }
}

/// The system spell checker, CLDR alphabets and the Natural Language recognizer.
@MainActor
public final class SystemLexicon: Lexicon {
    private var dictionaries: [String: String?] = [:]
    private var alphabets: [String: CharacterSet?] = [:]
    private var verdicts: [String: Bool] = [:]
    private let recognizer = NLLanguageRecognizer()

    public init() {}

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
