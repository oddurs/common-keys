import Foundation

/// One piece of evidence about a reading of the keys. A reading's score is a weighted sum of these,
/// so the weights can be fitted instead of chosen by hand.
public enum Feature: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    // About one reading.
    /// Punctuation trimmed from the end, like the `;` in `hello;`.
    case trailingPunctuation
    /// How badly the word breaks its script's spelling rules.
    case orthography
    /// Symbols inside the word, like the `/` in `/etta`.
    case symbols
    /// Letters outside the language's alphabet.
    case foreignLetters
    /// Letters only, all from the language's alphabet.
    case clean
    case knownWord
    case unknownWord
    /// The language has no dictionary to ask.
    case noDictionary
    /// In the word list shipped for a language without a dictionary.
    case listedWord
    /// For a converting method: the reading keeps to the language's syllables.
    case readingAccepted
    /// For a converting method: how far an accepted reading runs past four letters, capped.
    case readingLength
    case readingRejected
    /// For a converting method: nothing is known about how its readings look.
    case unmodeledMethod

    // About a pair of readings.
    /// What the user taught about these keys.
    case taught
    /// The language recognizer's preference between two readings in one script.
    case recognized
    /// How typical the reading on screen is of its language's words, by character model. Zero
    /// unless both languages have a model.
    case shownTypicality
    /// How typical the candidate reading is of its language's words. Zero unless both have a model.
    case meantTypicality
    /// Both readings are dictionary words, as with `an` and `αν`: the hardest case to call.
    case bothKnown
    /// The reading on screen is a word the user often types and keeps on that keyboard. Weighed by
    /// `Memory.personalized`, not by the shipped weights: synthetic data has no kept words.
    case shownKept
    /// The candidate reading is a word the user often types and keeps on its keyboard.
    case meantKept

    fileprivate static let index = Dictionary(uniqueKeysWithValues: allCases.enumerated().map { ($1, $0) })
}

public struct FeatureVector: Equatable, Sendable {
    private var values = [Double](repeating: 0, count: Feature.allCases.count)

    public init() {}

    public subscript(feature: Feature) -> Double {
        get { values[Feature.index[feature]!] }
        set { values[Feature.index[feature]!] = newValue }
    }

    /// The evidence for one reading over another.
    public static func - (lhs: FeatureVector, rhs: FeatureVector) -> FeatureVector {
        var result = FeatureVector()
        result.values = zip(lhs.values, rhs.values).map(-)
        return result
    }
}

/// How much each piece of evidence counts, and how much evidence it takes to act unasked.
public struct Weights: Codable, Equatable, Sendable {
    public var values: [Feature: Double]
    /// The score evidence must reach before a word is fixed without being asked.
    public var threshold: Double

    public init(_ values: [Feature: Double], threshold: Double) {
        self.values = values
        self.threshold = threshold
    }

    public func score(_ features: FeatureVector) -> Double {
        Feature.allCases.reduce(0) { $0 + (values[$1] ?? 0) * features[$1] }
    }

    /// The weights the engine was tuned with by hand: a symbol inside a word costs more than a
    /// misspelling, a dictionary word is worth the most.
    public static let hand = Weights(
        [
            .trailingPunctuation: -0.5,
            .orthography: -1,
            .symbols: -2,
            .foreignLetters: -0.5,
            .clean: 1,
            .knownWord: 3,
            .unknownWord: -1,
            .noDictionary: -0.5,
            .listedWord: 0,
            .readingAccepted: 2,
            .readingLength: 1,
            .readingRejected: -2,
            .unmodeledMethod: -1,
            .taught: 1,
            .recognized: 1,
            .shownTypicality: 0,
            .meantTypicality: 0,
            .bothKnown: 0,
            .shownKept: -3,
            .meantKept: 3,
        ], threshold: 2)
}
