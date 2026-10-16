import Carbon
import Foundation

/// A keyboard layout's key table, read with the system's own translator, so every layout macOS
/// ships or the user installs works the same way: 251 of them across 35 scripts on macOS 26.
public struct KeyLayout: Sendable {
    private let data: Data
    private let reverse: ReverseTable

    public init(data: Data) {
        self.data = data
        self.reverse = ReverseTable()
    }

    /// The characters the keys type, dead keys composed.
    public func characters(for strokes: [KeyStroke]) -> String {
        withLayout { layout in
            var deadKeys: UInt32 = 0
            var text = ""
            var lastTyped = ""
            for stroke in strokes {
                lastTyped = Self.translate(layout, stroke.keyCode, stroke.modifiers, &deadKeys)
                text += lastTyped
            }
            // A dangling dead key sits on screen as its bare accent until the next key. Layouts that
            // type a character and keep state for what may stack on it, like Tibetan, show nothing more.
            if deadKeys != 0, lastTyped.isEmpty {
                text += Self.translate(layout, 49, 0, &deadKeys).replacingOccurrences(of: " ", with: "")
            }
            return text
        }
    }

    /// The keys that type `text` on this layout, preferring single keys over dead-key pairs and
    /// plain keys over modified ones. Nil when some part of `text` is not on the layout.
    public func strokes(for text: String) -> [KeyStroke]? {
        let table = reverse.table { build() }
        let scalars = Array(text.unicodeScalars)
        var strokes: [KeyStroke] = []
        var index = 0
        while index < scalars.count {
            // Longest match first: one key can type several code points, as in Indic layouts.
            var matched = false
            for length in stride(from: min(table.longest, scalars.count - index), through: 1, by: -1) {
                var piece = String.UnicodeScalarView()
                piece.append(contentsOf: scalars[index..<index + length])
                if let keys = table.keys[String(piece)] {
                    strokes += keys
                    index += length
                    matched = true
                    break
                }
            }
            if !matched { return search(text) }
        }
        return strokes
    }

    /// Finds keys by typing them: for layouts whose keys chain through several dead-key states,
    /// as syllabaries like Ge'ez and Cherokee do, where no single key or pair maps to a character.
    private func search(_ text: String) -> [KeyStroke]? {
        let target = Array(text.unicodeScalars)
        let options = Self.allStrokes
        var failed: Set<[UInt32]> = []

        return withLayout { layout -> [KeyStroke]? in
            func walk(_ index: Int, _ state: UInt32, _ depth: Int) -> [KeyStroke]? {
                if index == target.count { return state == 0 ? [] : nil }
                let key: [UInt32] = [UInt32(index), state]
                guard depth < 4, !failed.contains(key) else { return nil }
                for stroke in options {
                    var next = state
                    let output = Array(
                        Self.translate(layout, stroke.keyCode, stroke.modifiers, &next).unicodeScalars)
                    if output.isEmpty {
                        guard next != 0, next != state, let rest = walk(index, next, depth + 1) else {
                            continue
                        }
                        return [stroke] + rest
                    }
                    guard index + output.count <= target.count,
                        Array(target[index..<index + output.count]) == output,
                        let rest = walk(index + output.count, next, 0)
                    else { continue }
                    return [stroke] + rest
                }
                failed.insert(key)
                return nil
            }
            return walk(0, 0, 0)
        }
    }

    private static let allStrokes: [KeyStroke] = {
        let codes = Array(UInt16(0)...50).filter { ![36, 48, 49].contains($0) } + [93, 94]
        return [(false, false), (true, false), (false, true), (true, true)].flatMap { shift, option in
            codes.map { KeyStroke($0, shift: shift, option: option) }
        }
    }()

    private func build() -> ReverseTable.Table {
        let codes = Array(UInt16(0)...50).filter { ![36, 48, 49].contains($0) } + [93, 94]
        // Cheapest first, so the first keys found for an output are the ones a person would press.
        let modifiers = [
            KeyStroke(0), KeyStroke(0, shift: true), KeyStroke(0, option: true),
            KeyStroke(0, shift: true, option: true),
        ]
        var keys: [String: [KeyStroke]] = [:]
        var deadKeys: [KeyStroke] = []
        withLayout { layout in
            for template in modifiers {
                for code in codes {
                    var stroke = template
                    stroke.keyCode = code
                    var state: UInt32 = 0
                    let output = Self.translate(layout, code, stroke.modifiers, &state)
                    if state != 0 {
                        deadKeys.append(stroke)
                    } else if !output.isEmpty, keys[output] == nil {
                        keys[output] = [stroke]
                    }
                }
            }
            for dead in deadKeys {
                for template in modifiers.prefix(2) {
                    for code in codes {
                        var stroke = template
                        stroke.keyCode = code
                        var state: UInt32 = 0
                        _ = Self.translate(layout, dead.keyCode, dead.modifiers, &state)
                        let output = Self.translate(layout, code, stroke.modifiers, &state)
                        if state == 0, !output.isEmpty, keys[output] == nil { keys[output] = [dead, stroke] }
                    }
                }
            }
        }
        let longest = keys.keys.map(\.unicodeScalars.count).max() ?? 1
        return ReverseTable.Table(keys: keys, longest: longest)
    }

    private func withLayout<T>(_ body: (UnsafePointer<UCKeyboardLayout>) -> T) -> T {
        data.withUnsafeBytes { raw in body(raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)) }
    }

    private static func translate(
        _ layout: UnsafePointer<UCKeyboardLayout>, _ keyCode: UInt16, _ modifiers: UInt32,
        _ deadKeys: inout UInt32
    ) -> String {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout, keyCode, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()), 0,
            &deadKeys, chars.count, &length, &chars)
        return status == noErr ? String(utf16CodeUnits: chars, count: length) : ""
    }
}

/// The output-to-keys table, built on first use: most layouts are never asked to reverse.
private final class ReverseTable: @unchecked Sendable {
    struct Table {
        var keys: [String: [KeyStroke]]
        var longest: Int
    }

    private let lock = NSLock()
    private var built: Table?

    func table(_ build: () -> Table) -> Table {
        lock.lock()
        defer { lock.unlock() }
        if let built { return built }
        let table = build()
        built = table
        return table
    }
}

extension KeyStroke {
    /// Modifier state in the form `UCKeyTranslate` expects: Carbon modifier bits shifted down a byte.
    var modifiers: UInt32 {
        var bits = 0
        if shift { bits |= shiftKey }
        if option { bits |= optionKey }
        if capsLock { bits |= alphaLock }
        return UInt32((bits >> 8) & 0xFF)
    }
}
