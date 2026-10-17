import Foundation

/// How a language's words are spelled: character 4-grams with stupid backoff. It answers "how much
/// does this look like a word of the language", graded, for any script, which a dictionary cannot.
public struct CharacterModel: Sendable {
    private static let order = 4
    private static let start: Unicode.Scalar = "\u{2}"
    private static let end: Unicode.Scalar = "\u{3}"

    /// Every n-gram up to `order` scalars long, start and end marks included, as sorted hashes with
    /// their counts: 12 bytes an entry, a few hundred kilobytes a language, searched by bisection.
    private var keys: [UInt64] = []
    private var counts: [UInt32] = []
    private var characters = 0
    private var alphabet = 0
    /// The mean and spread of the model's own words' naturalness, so scores from languages with
    /// different alphabets and different-sized lists can be compared.
    private var typical = (mean: 0.0, spread: 1.0)

    public init(words: some Collection<String>) {
        var tally: [UInt64: UInt32] = [:]
        var letters: Set<Unicode.Scalar> = []
        for word in words {
            let scalars = Self.padded(word, complete: true)
            for i in scalars.indices {
                for length in 1...Self.order where i + length <= scalars.count {
                    tally[Self.hash(scalars[i..<i + length]), default: 0] += 1
                }
                if scalars[i] != Self.start {
                    characters += 1
                    letters.insert(scalars[i])
                }
            }
        }
        let sorted = tally.sorted { $0.key < $1.key }
        keys = sorted.map(\.key)
        counts = sorted.map(\.value)
        alphabet = letters.count
        // Every word's own score, or an even sample of them: cheap, and enough for a mean and spread.
        let all = Array(words)
        let step = max(1, all.count / 2000)
        let scores = stride(from: 0, to: all.count, by: step).map { naturalness(all[$0]) }
        if scores.count > 1 {
            let mean = scores.reduce(0, +) / Double(scores.count)
            let variance = scores.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(scores.count - 1)
            typical = (mean, max(variance.squareRoot(), 0.1))
        }
    }

    private func count(_ gram: ArraySlice<Unicode.Scalar>) -> Int {
        let key = Self.hash(gram)
        var low = 0
        var high = keys.count
        while low < high {
            let middle = (low + high) / 2
            if keys[middle] < key { low = middle + 1 } else { high = middle }
        }
        return low < keys.count && keys[low] == key ? Int(counts[low]) : 0
    }

    /// FNV-1a over the scalars. Collisions among a language's few hundred thousand n-grams are rare
    /// enough to ignore at 64 bits.
    private static func hash(_ gram: ArraySlice<Unicode.Scalar>) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for scalar in gram {
            hash ^= UInt64(scalar.value)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// How typical `text` is of the language's words, in spreads from their mean: around zero for an
    /// ordinary word, far below for noise. Comparable across languages, unlike `naturalness`.
    public func typicality(_ text: String, complete: Bool = true) -> Double {
        (naturalness(text, complete: complete) - typical.mean) / typical.spread
    }

    public var isEmpty: Bool { characters == 0 }

    /// Bits per character above a uniform guess over the language's letters: positive reads like the
    /// language, negative reads like noise. `complete` scores the end of the word too.
    public func naturalness(_ text: String, complete: Bool = true) -> Double {
        let scalars = Self.padded(text, complete: complete)
        let positions = (Self.order - 1)..<scalars.count
        guard !positions.isEmpty, characters > 0 else { return 0 }
        var bits = 0.0
        for i in positions {
            var backoff = 1.0
            var probability = 0.0
            for context in stride(from: Self.order - 1, through: 0, by: -1) {
                let seen = count(scalars[(i - context)...i])
                let given = context == 0 ? characters : count(scalars[(i - context)..<i])
                if seen > 0, given > 0 {
                    probability = backoff * Double(seen) / Double(given)
                    break
                }
                backoff *= 0.4
            }
            // A character the language never uses: the least likely thing there is.
            if probability == 0 { probability = backoff / Double(characters + alphabet + 1) }
            bits += log2(probability)
        }
        return bits / Double(positions.count) + log2(Double(alphabet + 1))
    }

    private static func padded(_ text: String, complete: Bool) -> [Unicode.Scalar] {
        let scalars = text.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars
        return Array(repeating: start, count: order - 1) + scalars + (complete ? [end] : [])
    }
}

/// Word lists shipped for languages macOS has no dictionary for, from `scripts/wordlists`.
public enum WordLists {
    public static func shipped(_ language: String) -> [String]? {
        text(language)?.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

extension Keyboard {
    /// What two keys type, where both are letters: starts for listing a language's words from the
    /// spell checker, in this keyboard's own alphabet or syllables.
    public var twoKeyStarts: [String] {
        let keys = (UInt16(0)...50).filter { KeyKind(keyCode: $0) == .character }.map { KeyStroke($0) }
        var starts: Set<String> = []
        for first in keys {
            for second in keys {
                let text = self.text(for: [first, second]).lowercased()
                if !text.isEmpty, text.count <= 2, text.allSatisfy(\.isLetter) { starts.insert(text) }
            }
        }
        return starts.sorted()
    }
}
