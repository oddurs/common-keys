import Foundation

/// Assembles a layout's raw characters into syllables, the way an input method does.
public protocol Composer: Sendable {
    func compose(_ raw: String) -> String
    /// The raw characters that compose into `text`, or nil when it cannot be composed.
    func decompose(_ text: String) -> String?
    /// Backspaces that remove `raw` while its last syllable is still being composed.
    func pendingErasures(_ raw: String) -> Int
}

extension Composer {
    public func pendingErasures(_ raw: String) -> Int { compose(raw).count }
}

/// Korean Dubeolsik (2-Set): consonant and vowel keys combine into syllable blocks, with the
/// standard compound vowels and finals, and a final consonant moving on when a vowel follows.
public struct HangulComposer: Composer {
    private static let initials = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let medials = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    /// Index 0 is "no final".
    private static let finals = Array("_ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
    private static let vowelPairs: [String: Character] = [
        "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ",
    ]
    private static let finalPairs: [String: Character] = [
        "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ", "ㄹㅅ": "ㄽ",
        "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ",
    ]
    private static let splitVowels = Dictionary(uniqueKeysWithValues: vowelPairs.map { ($0.value, $0.key) })
    private static let splitFinals = Dictionary(uniqueKeysWithValues: finalPairs.map { ($0.value, $0.key) })

    public init() {}

    private enum Piece {
        case syllable(initial: Character?, medial: Character?, final: Character?, keys: Int)
        case other(Character)

        var text: String {
            switch self {
            case .other(let character):
                return String(character)
            case .syllable(let initial, let medial, let final, _):
                guard let initial, let medial, let l = HangulComposer.initials.firstIndex(of: initial),
                    let v = HangulComposer.medials.firstIndex(of: medial)
                else { return [initial, medial].compactMap { $0 }.map(String.init).joined() }
                let t = final.flatMap { HangulComposer.finals.firstIndex(of: $0) } ?? 0
                return String(UnicodeScalar(0xAC00 + (l * 21 + v) * 28 + t)!)
            }
        }
    }

    public func compose(_ raw: String) -> String {
        pieces(raw).map(\.text).joined()
    }

    public func pendingErasures(_ raw: String) -> Int {
        let pieces = pieces(raw)
        guard case .syllable(_, _, _, let keys) = pieces.last else { return pieces.count }
        return pieces.count - 1 + keys
    }

    private func pieces(_ raw: String) -> [Piece] {
        var done: [Piece] = []
        var initial: Character?
        var medial: Character?
        var final: Character?
        var keys = 0

        func flush() {
            if initial != nil || medial != nil {
                done.append(.syllable(initial: initial, medial: medial, final: final, keys: keys))
            }
            (initial, medial, final, keys) = (nil, nil, nil, 0)
        }

        for character in raw {
            if Self.initials.contains(character) || Self.finals.dropFirst().contains(character) {
                if let current = final, let pair = Self.finalPairs["\(current)\(character)"] {
                    final = pair
                    keys += 1
                } else if initial != nil, medial != nil, final == nil,
                    Self.finals.dropFirst().contains(character)
                {
                    final = character
                    keys += 1
                } else {
                    flush()
                    initial = character
                    keys = 1
                }
            } else if Self.medials.contains(character) {
                if let current = final {
                    // The final consonant starts the next syllable; a compound final gives up its second half.
                    let split = Self.splitFinals[current].map(Array.init)
                    final = split?.first
                    keys -= 1
                    let moving = split?.last ?? current
                    flush()
                    (initial, medial, keys) = (moving, character, 2)
                } else if let current = medial, let pair = Self.vowelPairs["\(current)\(character)"] {
                    medial = pair
                    keys += 1
                } else if medial == nil, initial != nil {
                    medial = character
                    keys += 1
                } else {
                    flush()
                    medial = character
                    keys = 1
                }
            } else {
                flush()
                done.append(.other(character))
            }
        }
        flush()
        return done
    }

    public func decompose(_ text: String) -> String? {
        var raw = ""
        for scalar in text.unicodeScalars {
            let value = Int(scalar.value)
            guard (0xAC00...0xD7A3).contains(value) else {
                raw.unicodeScalars.append(scalar)
                continue
            }
            let index = value - 0xAC00
            let (l, v, t) = (index / (21 * 28), (index % (21 * 28)) / 28, index % 28)
            raw.append(Self.initials[l])
            let medial = Self.medials[v]
            raw += Self.splitVowels[medial] ?? String(medial)
            if t > 0 {
                let final = Self.finals[t]
                raw += Self.splitFinals[final] ?? String(final)
            }
        }
        return raw
    }
}

/// Vietnamese Telex and VNI: letters or digits typed after a vowel add its diacritics and tone.
public struct VietnameseComposer: Composer {
    public enum Method: Sendable { case telex, vni }

    public let method: Method

    public init(_ method: Method) {
        self.method = method
    }

    private enum Tone: Character, CaseIterable {
        case acute = "\u{301}"
        case grave = "\u{300}"
        case hook = "\u{309}"
        case tilde = "\u{303}"
        case dot = "\u{323}"
    }

    private static let vowels = Set("aăâeêioôơuưy")

    public func compose(_ raw: String) -> String {
        var output = ""
        var word: [Character] = []
        var tone: Tone?
        for character in raw {
            if character.isLetter || (method == .vni && character.isNumber) {
                apply(character, to: &word, tone: &tone)
            } else {
                output += render(word, tone)
                output.append(character)
                word = []
                tone = nil
            }
        }
        return output + render(word, tone)
    }

    private func apply(_ typed: Character, to word: inout [Character], tone: inout Tone?) {
        let key = Character(typed.lowercased())
        let upper = typed.isUppercase
        let hasVowel = word.contains { Self.vowels.contains(Character($0.lowercased())) }

        if let newTone = toneKey(key), hasVowel {
            if tone == newTone {
                tone = nil
                word.append(typed)
            } else {
                tone = newTone
            }
            return
        }
        if key == (method == .telex ? "z" : "0"), tone != nil {
            tone = nil
            return
        }
        if let marked = mark(key, on: &word) {
            if !marked { word.append(typed) }
            return
        }
        word.append(upper ? Character(key.uppercased()) : key)
    }

    private func toneKey(_ key: Character) -> Tone? {
        switch (method, key) {
        case (.telex, "s"), (.vni, "1"): .acute
        case (.telex, "f"), (.vni, "2"): .grave
        case (.telex, "r"), (.vni, "3"): .hook
        case (.telex, "x"), (.vni, "4"): .tilde
        case (.telex, "j"), (.vni, "5"): .dot
        default: nil
        }
    }

    /// Applies a diacritic key. Nil when `key` is no diacritic key; false when it had nothing to mark.
    private func mark(_ key: Character, on word: inout [Character]) -> Bool? {
        let lower = word.map { Character($0.lowercased()) }
        func replace(_ index: Int, with plain: Character) {
            word[index] = word[index].isUppercase ? Character(plain.uppercased()) : plain
        }
        switch (method, key) {
        case (.telex, "d"), (.vni, "9"):
            guard let index = lower.firstIndex(of: "d"), index == 0, method == .vni || lower.last == "d"
            else {
                return method == .telex ? nil : false
            }
            replace(index, with: "đ")
            return true
        case (.telex, "a"), (.telex, "e"), (.telex, "o"), (.vni, "6"):
            let targets: [Character: Character] = ["a": "â", "e": "ê", "o": "ô"]
            let candidates = method == .telex ? [key] : ["a", "e", "o"]
            guard let index = lower.lastIndex(where: { candidates.contains($0) }) else {
                return method == .telex ? nil : false
            }
            // Telex only doubles a vowel of the current vowel run, so "taoa" is not "tâo".
            if method == .telex, lower[(index + 1)...].contains(where: { !Self.vowels.contains($0) }) {
                return nil
            }
            replace(index, with: targets[lower[index]]!)
            return true
        case (.telex, "w"), (.vni, "7"), (.vni, "8"):
            if let o = lower.lastIndex(of: "o"), o > 0, lower[o - 1] == "u" || lower[o - 1] == "ư", key != "8" {
                replace(o - 1, with: "ư")
                replace(o, with: "ơ")
                return true
            }
            let horn: [Character: Character] = key == "8" ? ["a": "ă"] : ["o": "ơ", "u": "ư", "a": "ă"]
            guard let index = lower.lastIndex(where: { horn[$0] != nil }) else {
                if method == .telex {
                    word.append("ư")
                    return true
                }
                return false
            }
            replace(index, with: horn[lower[index]]!)
            return true
        default:
            return nil
        }
    }

    private func render(_ word: [Character], _ tone: Tone?) -> String {
        guard let tone, let index = toneIndex(word) else { return String(word) }
        var marked = word
        let base = String(marked[index]).decomposedStringWithCanonicalMapping
        marked[index] = Character((base + String(tone.rawValue)).precomposedStringWithCanonicalMapping)
        return String(marked)
    }

    /// Where the tone mark goes, by the modern rules.
    private func toneIndex(_ word: [Character]) -> Int? {
        let lower = word.map { Character($0.lowercased()) }
        guard var first = lower.firstIndex(where: { Self.vowels.contains($0) }) else { return nil }
        // In "qu" and "gi" the vowel letter belongs to the consonant.
        if first > 0,
            (lower[first - 1] == "q" && lower[first] == "u")
                || (lower[first - 1] == "g" && lower[first] == "i"),
            first + 1 < lower.count, Self.vowels.contains(lower[first + 1])
        {
            first += 1
        }
        var end = first
        while end + 1 < lower.count, Self.vowels.contains(lower[end + 1]) { end += 1 }
        let cluster = Array(lower[first...end])
        if let marked = cluster.lastIndex(where: { "ăâêôơư".contains($0) }) {
            return first
                + (cluster[marked] == "ư" && cluster.count > marked + 1 && cluster[marked + 1] == "ơ"
                    ? marked + 1 : marked)
        }
        let closed = end + 1 < lower.count
        switch cluster.count {
        case 1: return first
        case 2: return closed || ["oa", "oe", "uy"].contains(String(cluster)) ? first + 1 : first
        default: return first + 1
        }
    }

    public func decompose(_ text: String) -> String? {
        var raw = ""
        var pendingTone: Character?
        let marks: [Character: String] =
            method == .telex
            ? ["â": "aa", "ă": "aw", "ê": "ee", "ô": "oo", "ơ": "ow", "ư": "uw", "đ": "dd"]
            : ["â": "a6", "ă": "a8", "ê": "e6", "ô": "o6", "ơ": "o7", "ư": "u7", "đ": "d9"]
        let tones: [Character: Character] =
            method == .telex
            ? ["\u{301}": "s", "\u{300}": "f", "\u{309}": "r", "\u{303}": "x", "\u{323}": "j"]
            : ["\u{301}": "1", "\u{300}": "2", "\u{309}": "3", "\u{303}": "4", "\u{323}": "5"]
        for character in text {
            guard character.isLetter else {
                if let tone = pendingTone { raw.append(tone) }
                pendingTone = nil
                raw.append(character)
                continue
            }
            var base = ""
            for scalar in String(character).decomposedStringWithCanonicalMapping.unicodeScalars {
                if let tone = tones[Character(scalar)] {
                    pendingTone = tone
                } else {
                    base.unicodeScalars.append(scalar)
                }
            }
            let letter = Character(base.precomposedStringWithCanonicalMapping)
            let lower = Character(letter.lowercased())
            if let spelled = marks[lower] {
                raw += letter.isUppercase ? spelled.prefix(1).uppercased() + spelled.dropFirst() : spelled
            } else {
                raw.append(letter)
            }
        }
        if let tone = pendingTone { raw.append(tone) }
        return raw
    }
}
