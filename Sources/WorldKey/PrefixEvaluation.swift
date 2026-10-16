import Foundation

/// How well the engine decides mid-word: every start of a word, three keys or more, typed on the
/// right keyboard (anything changed is a false fix) and on each wrong one (how early it is fixed).
public struct PrefixEvaluation: Encodable, Sendable {
    public struct Source: Encodable, Sendable {
        public var keyboard: String
        public var prefixes: Int
        public var falseFixes: Int
        public var examples: [String]
    }

    public struct Pair: Encodable, Sendable {
        public var meant: String
        public var typedOn: String
        public var words: Int
        /// Words fixed before they were finished.
        public var fixedEarly: Int
        /// Keys typed before the fix, summed over the words fixed early.
        public var keysBeforeFix: Int
        /// Keys in those words, summed, to put `keysBeforeFix` in proportion.
        public var keysInWords: Int
    }

    public var sources: [Source] = []
    public var pairs: [Pair] = []

    public var table: String {
        var lines = ["Starts of words typed on the right keyboard (changed anyway is a false fix):"]
        for source in sources {
            lines.append(
                "  \(source.keyboard)  \(source.prefixes) starts, \(source.falseFixes) false fixes"
                    + (source.examples.isEmpty ? "" : "  e.g. " + source.examples.joined(separator: ", ")))
        }
        lines.append("Words typed on the wrong keyboard (fixed before the word ends, and how far in):")
        for pair in pairs {
            let early = pair.words == 0 ? 0 : 100 * Double(pair.fixedEarly) / Double(pair.words)
            let at = pair.keysInWords == 0 ? 0 : 100 * Double(pair.keysBeforeFix) / Double(pair.keysInWords)
            lines.append(
                String(
                    format: "  meant %@, typed on %@: %d/%d fixed early (%.0f%%), at %.0f%% of the word", pair.meant,
                    pair.typedOn, pair.fixedEarly, pair.words, early, at))
        }
        return lines.joined(separator: "\n")
    }
}

extension Evaluation {
    @MainActor
    public static func prefixes(
        _ keyboards: [any Keyboard], words count: Int, lexicon: SystemLexicon, detector: Detector = Detector(),
        split: Split = .all
    ) -> PrefixEvaluation {
        var report = PrefixEvaluation()
        if split == .heldOut { lexicon.modelSplit = .models }
        defer { lexicon.modelSplit = .all }
        func starts(_ strokes: [KeyStroke]) -> [[KeyStroke]] {
            strokes.count > 3 ? (3..<strokes.count).map { Array(strokes.prefix($0)) } : []
        }
        for meant in keyboards where meant.kind != .converting && lexicon.wordList(for: meant) != nil {
            let words = sample(meant, count, lexicon, split: split)
            var source = PrefixEvaluation.Source(keyboard: meant.id, prefixes: 0, falseFixes: 0, examples: [])
            for (word, strokes) in words {
                for start in starts(strokes) {
                    source.prefixes += 1
                    if let fix = detector.decidePrefix(
                        start, typedIn: meant, candidates: keyboards, memory: Memory(), lexicon: lexicon)
                    {
                        source.falseFixes += 1
                        if source.examples.count < 8 {
                            source.examples.append("\(word): \(fix.original)→\(fix.replacement)")
                        }
                    }
                }
            }
            report.sources.append(source)

            for typed in keyboards where typed.id != meant.id && typed.kind == .direct {
                var pair = PrefixEvaluation.Pair(
                    meant: meant.id, typedOn: typed.id, words: 0, fixedEarly: 0, keysBeforeFix: 0, keysInWords: 0)
                for (word, strokes) in words where strokes.count > 3 && typed.text(for: strokes) != word {
                    pair.words += 1
                    for start in starts(strokes) {
                        guard
                            let fix = detector.decidePrefix(
                                start, typedIn: typed, candidates: keyboards, memory: Memory(), lexicon: lexicon)
                        else { continue }
                        if fix.replacement == meant.text(for: start) {
                            pair.fixedEarly += 1
                            pair.keysBeforeFix += start.count
                            pair.keysInWords += strokes.count
                        }
                        break
                    }
                }
                report.pairs.append(pair)
            }
        }
        return report
    }
}
