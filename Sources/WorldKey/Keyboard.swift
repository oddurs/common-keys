import Foundation

/// How a keyboard turns keys into text.
public enum KeyboardKind: String, Sendable, Codable, CaseIterable {
    /// Each key types its character at once: every ordinary layout, dead keys included.
    case direct
    /// Keys build syllables by fixed rules, like Korean 2-Set or Vietnamese Telex. The result is
    /// predictable, so text typed in one can be read, and written, by the engine.
    case composing
    /// Keys spell a reading that an input method converts into text the user picks, like Japanese
    /// or Chinese. The result cannot be predicted, so the engine only ever hands these the keys.
    case converting
}

/// Anything that turns physical keys into text: a layout, or an input method built on one.
public protocol Keyboard: Sendable {
    var id: String { get }
    var name: String { get }
    /// BCP 47 code of the keyboard's main language, such as "en", "is" or "zh-Hans".
    var language: String { get }
    var kind: KeyboardKind { get }
    /// What the keys type. For a converting keyboard, the reading they spell, such as romaji.
    func text(for strokes: [KeyStroke]) -> String
    /// The keys that type `text`, if this keyboard can type it at all.
    func strokes(for text: String) -> [KeyStroke]?
    /// Backspaces that remove what `strokes` typed. `committed` is false while an input method
    /// is still composing the last syllable, which it then takes apart one key at a time.
    func erasures(for strokes: [KeyStroke], committed: Bool) -> Int
}

extension Keyboard {
    public func erasures(for strokes: [KeyStroke], committed: Bool) -> Int {
        text(for: strokes).count
    }

    /// The language part of the code, for spell checking: "zh-Hans" is "zh".
    public var baseLanguage: String {
        String(language.split(separator: "-").first ?? Substring(language))
    }

    public var code: String { baseLanguage.uppercased() }

    /// The flag of the keyboard's country, or its language code when it has none.
    public var flag: String {
        guard let region else { return code }
        let scalars = region.unicodeScalars.compactMap { UnicodeScalar(0x1F1E6 - 0x41 + $0.value) }
        return String(String.UnicodeScalarView(scalars))
    }

    var region: String? {
        let name = id.split(separator: ".").last.map(String.init) ?? id
        if let region = Self.layoutRegions.first(where: { name.hasPrefix($0.key) })?.value { return region }
        guard baseLanguage != "und", !baseLanguage.isEmpty else { return nil }
        let likely = Locale.Language(identifier: Locale.Language(identifier: language).maximalIdentifier)
        return likely.region?.identifier
    }

    /// Layouts named for a country other than their language's most likely one.
    private static var layoutRegions: [String: String] {
        [
            "British": "GB", "Australian": "AU", "Canadian": "CA", "Irish": "IE", "Swiss": "CH",
            "Austrian": "AT", "Belgian": "BE", "Brazilian": "BR", "Portuguese": "PT", "LatinAmerican": "MX",
            "TCIM": "TW", "TYIM": "HK",
        ]
    }
}

/// An ordinary layout: keys type characters, dead keys and all.
public struct LayoutKeyboard: Keyboard, Identifiable {
    public let id: String
    public let name: String
    public let language: String
    public let layout: KeyLayout
    public var kind: KeyboardKind { .direct }

    public init(id: String, name: String, language: String, layout: KeyLayout) {
        self.id = id
        self.name = name
        self.language = language
        self.layout = layout
    }

    public func text(for strokes: [KeyStroke]) -> String { layout.characters(for: strokes) }
    public func strokes(for text: String) -> [KeyStroke]? { layout.strokes(for: text) }
}

/// A layout whose characters a composer assembles into syllables.
public struct ComposedKeyboard: Keyboard, Identifiable {
    public let id: String
    public let name: String
    public let language: String
    public let layout: KeyLayout
    public let composer: any Composer
    public var kind: KeyboardKind { .composing }

    public init(id: String, name: String, language: String, layout: KeyLayout, composer: any Composer) {
        self.id = id
        self.name = name
        self.language = language
        self.layout = layout
        self.composer = composer
    }

    public func text(for strokes: [KeyStroke]) -> String {
        composer.compose(layout.characters(for: strokes))
    }

    public func strokes(for text: String) -> [KeyStroke]? {
        composer.decompose(text).flatMap(layout.strokes(for:))
    }

    public func erasures(for strokes: [KeyStroke], committed: Bool) -> Int {
        let raw = layout.characters(for: strokes)
        return committed ? composer.compose(raw).count : composer.pendingErasures(raw)
    }
}

/// An input method that converts a spelled reading into text the user chooses.
public struct ConvertingKeyboard: Keyboard, Identifiable {
    public let id: String
    public let name: String
    public let language: String
    public let layout: KeyLayout
    /// Whether a reading looks like this language, when the engine knows how to tell.
    public let phonotactics: Phonotactics?
    public var kind: KeyboardKind { .converting }

    public init(id: String, name: String, language: String, layout: KeyLayout, phonotactics: Phonotactics?) {
        self.id = id
        self.name = name
        self.language = language
        self.layout = layout
        self.phonotactics = phonotactics
    }

    public func text(for strokes: [KeyStroke]) -> String { layout.characters(for: strokes) }
    public func strokes(for text: String) -> [KeyStroke]? { layout.strokes(for: text) }
}
