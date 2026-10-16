import Foundation

public struct TrackedWord: Equatable, Sendable {
    public var strokes: [KeyStroke]
    public var layoutID: String
}

/// A finished word still directly before the cursor, with the key that ended it.
public struct EndedWord: Equatable, Sendable {
    public var word: TrackedWord
    public var boundary: KeyStroke
}

/// Evidence of a wrong-layout word: the user erased it and typed the same keys in another layout.
public struct Retype: Equatable, Sendable {
    public var strokes: [KeyStroke]
    public var from: String
    public var to: String
}

/// Follows the word under the cursor from raw key events. It only trusts what it saw: anything
/// it cannot model, such as a click, an arrow key or a shortcut, clears it.
public struct WordTracker: Sendable {
    public private(set) var current: [KeyStroke] = []
    public private(set) var previous: EndedWord?
    /// The active layout.
    public private(set) var layoutID: String
    /// The layout `current` was typed in.
    private var wordLayoutID: String
    /// `current` as it stood before the user began backspacing through it.
    private var typed: [KeyStroke] = []
    private var erased: [(word: TrackedWord, at: Date)] = []
    private let retypeWindow: TimeInterval = 60

    public init(layoutID: String) {
        self.layoutID = layoutID
        self.wordLayoutID = layoutID
    }

    public var currentWord: TrackedWord? {
        current.isEmpty ? nil : TrackedWord(strokes: current, layoutID: wordLayoutID)
    }

    public mutating func type(_ stroke: KeyStroke) {
        // Half a word in each layout is nothing we can reason about; start over.
        if !current.isEmpty && wordLayoutID != layoutID { current = [] }
        if current.isEmpty { wordLayoutID = layoutID }
        current.append(stroke)
        typed = current
    }

    public mutating func backspace(wholeWord: Bool, now: Date) {
        if current.isEmpty {
            guard let ended = previous else { return }
            // Deleting the boundary puts the cursor back at the end of the previous word.
            previous = nil
            current = ended.word.strokes
            typed = current
            wordLayoutID = ended.word.layoutID
        }
        if wholeWord { current.removeAll() } else { current.removeLast() }
        if current.isEmpty, !typed.isEmpty {
            erased.append((TrackedWord(strokes: typed, layoutID: wordLayoutID), now))
            erased.removeFirst(max(0, erased.count - 8))
            typed = []
        }
    }

    public mutating func end(with boundary: KeyStroke, now: Date) -> Retype? {
        guard let word = currentWord else {
            previous = nil
            return nil
        }
        current = []
        typed = []
        previous = EndedWord(word: word, boundary: boundary)

        erased.removeAll { now.timeIntervalSince($0.at) > retypeWindow }
        guard
            let index = erased.lastIndex(where: {
                $0.word.layoutID != word.layoutID && $0.word.strokes.signature == word.strokes.signature
            })
        else { return nil }
        let from = erased.remove(at: index).word.layoutID
        return Retype(strokes: word.strokes, from: from, to: word.layoutID)
    }

    public mutating func setLayout(_ id: String) {
        layoutID = id
    }

    /// Records that the word in progress now reads in `id`, after converting it.
    public mutating func relabelCurrent(_ id: String) {
        wordLayoutID = id
    }

    /// Records that the previous word now reads in `id`, after converting it.
    public mutating func relabelPrevious(_ id: String) {
        previous?.word.layoutID = id
    }

    /// Forgets the cursor context. Erased words survive: a click between erasing and retyping
    /// does not make the retype any less telling.
    public mutating func reset() {
        current = []
        typed = []
        previous = nil
    }
}
