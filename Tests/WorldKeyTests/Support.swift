import Foundation
import WorldKey

/// US key codes by the character they type, enough to spell test words.
let usKeys: [Character: UInt16] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
    "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "=": 24, "-": 27, "]": 30, "o": 31, "u": 32, "[": 33,
    "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45,
    "m": 46, ".": 47, "`": 50,
]

/// The keys a US typist presses to produce `text`.
func keys(_ text: String) -> [KeyStroke] {
    text.map { KeyStroke(usKeys[$0]!) }
}

struct FakeLayout: Keyboard {
    let id: String
    let name: String
    let language: String
    let table: [UInt16: String]
    var kind: KeyboardKind { .direct }

    func strokes(for text: String) -> [KeyStroke]? {
        let reverse = Dictionary(table.map { ($0.value, $0.key) }, uniquingKeysWith: min)
        var strokes: [KeyStroke] = []
        for character in text {
            guard let code = reverse[String(character).lowercased()] else { return nil }
            strokes.append(KeyStroke(code, shift: character.isUppercase))
        }
        return strokes
    }

    func text(for strokes: [KeyStroke]) -> String {
        strokes.map { stroke in
            let plain = table[stroke.keyCode] ?? ""
            return stroke.shift ? plain.uppercased() : plain
        }.joined()
    }

    static let us = FakeLayout(
        id: "us", name: "U.S.", language: "en",
        table: Dictionary(uniqueKeysWithValues: usKeys.map { ($0.value, String($0.key)) }))

    static let icelandic = FakeLayout(
        id: "is", name: "Icelandic", language: "is",
        table: us.table.merging([27: "ö", 24: "-", 30: "'", 33: "ð", 39: "´", 41: "æ", 42: "+", 44: "þ"]) {
            $1
        })
}

@MainActor
struct FakeLexicon: Lexicon {
    func startsWord(_ prefix: String, language: String) -> Bool? {
        words[language].map { $0.contains { $0.hasPrefix(prefix.lowercased()) } }
    }

    var words: [String: Set<String>] = [
        "en": ["test", "the", "pat", "don't", "hello"],
        "is": ["þetta", "það", "bæ", "test"],
    ]

    func isWord(_ word: String, language: String) -> Bool? {
        words[language].map { $0.contains(word.lowercased()) }
    }

    func alphabet(for language: String) -> CharacterSet? {
        switch language {
        case "en": CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        case "is": CharacterSet(charactersIn: "aábdðeéfghiíjklmnoóprstuúvxyýþæö")
        default: nil
        }
    }
}

/// One lexicon for every test that asks the system: its character models take seconds to build.
@MainActor let sharedLexicon = SystemLexicon()
