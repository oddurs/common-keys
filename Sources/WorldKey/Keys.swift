/// One physical key press. Detection and learning work on these rather than on characters,
/// because the same key means a different letter in each layout.
public struct KeyStroke: Hashable, Codable, Sendable {
    public var keyCode: UInt16
    public var shift: Bool
    public var option: Bool
    public var capsLock: Bool

    public init(_ keyCode: UInt16, shift: Bool = false, option: Bool = false, capsLock: Bool = false) {
        self.keyCode = keyCode
        self.shift = shift
        self.option = option
        self.capsLock = capsLock
    }
}

/// What a key does to the word under the cursor.
public enum KeyKind: Sendable, Equatable {
    case character
    case backspace
    case boundary
    case other

    public init(keyCode: UInt16) {
        switch keyCode {
        case 51: self = .backspace
        case 36, 48, 49, 76: self = .boundary  // return, tab, space, keypad enter
        // Every printable key belongs to the word, punctuation included: `;` on one layout is `æ` on another.
        case 0...50, 93, 94: self = .character
        default: self = .other
        }
    }
}

extension Array where Element == KeyStroke {
    /// Identity of a word as physical keys, ignoring case, so "Þetta" and "þetta" learn together.
    public var signature: String {
        map { String($0.keyCode) }.joined(separator: ".")
    }
}
