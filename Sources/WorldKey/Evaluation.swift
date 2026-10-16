import Foundation

/// How well detection works on real words: each keyboard's dictionary words, typed once on the
/// right keyboard (anything changed is a false fix) and once on each wrong one (should be fixed).
public struct Evaluation: Encodable, Sendable {
    public struct Pair: Encodable, Sendable {
        public var meant: String
        public var typedOn: String
        public var words: Int
        /// Words that read the same on both keyboards, so nobody could tell.
        public var identical: Int
        /// Words fixed back to the right keyboard.
        public var fixed: Int
        /// Words fixed to a third keyboard instead.
        public var misfixed: Int
        public var missed: [String] = []
    }

    public struct Source: Encodable, Sendable {
        public var keyboard: String
        public var words: Int
        /// Correctly typed words the engine changed anyway.
        public var falseFixes: Int
        public var examples: [String]
    }

    public var sources: [Source] = []
    /// Mean time to judge one word, in milliseconds: this runs between a key press and the app.
    public var millisecondsPerWord: Double = 0
    public var pairs: [Pair] = []
    public var skipped: [String] = []

    @MainActor
    public static func run(
        _ keyboards: [any Keyboard], words count: Int, lexicon: SystemLexicon, detector: Detector = Detector(),
        split: Split = .all
    ) -> Evaluation {
        var report = Evaluation()
        let clock = ContinuousClock()
        var elapsed = Duration.zero
        var judged = 0

        for meant in keyboards {
            guard meant.kind != .converting, lexicon.hasDictionary(meant.baseLanguage) else {
                report.skipped.append(meant.id)
                continue
            }
            let words = sample(meant, count, lexicon, split: split)
            var source = Source(keyboard: meant.id, words: words.count, falseFixes: 0, examples: [])
            for (word, strokes) in words {
                if let fix = detector.decide(
                    strokes, typedIn: meant, candidates: keyboards, memory: Memory(), lexicon: lexicon)
                {
                    source.falseFixes += 1
                    if source.examples.count < 8 { source.examples.append("\(word)→\(fix.replacement)") }
                }
            }
            report.sources.append(source)

            for typed in keyboards where typed.id != meant.id && typed.kind != .converting {
                var pair = Pair(
                    meant: meant.id, typedOn: typed.id, words: words.count, identical: 0, fixed: 0,
                    misfixed: 0)
                for (word, strokes) in words {
                    if typed.text(for: strokes) == word {
                        pair.identical += 1
                        continue
                    }
                    let start = clock.now
                    let fix = detector.decide(
                        strokes, typedIn: typed, candidates: keyboards, memory: Memory(), lexicon: lexicon)
                    elapsed += clock.now - start
                    judged += 1
                    // Keyboards that read these keys the same, like Russian and Ukrainian often do, are
                    // equally right.
                    if fix?.targetID == meant.id || fix?.replacement == word {
                        pair.fixed += 1
                    } else if fix != nil {
                        pair.misfixed += 1
                    } else if pair.missed.count < 8 {
                        pair.missed.append("\(typed.text(for: strokes))→\(word)")
                    }
                }
                report.pairs.append(pair)
            }
        }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        report.millisecondsPerWord = judged == 0 ? 0 : 1000 * seconds / Double(judged)
        return report
    }

    /// Dictionary words the keyboard can type, gathered from the spell checker's completions for
    /// the syllables or letters its keys produce.
    @MainActor
    static func sample(_ keyboard: any Keyboard, _ count: Int, _ lexicon: SystemLexicon, split: Split = .all)
        -> [(String, [KeyStroke])]
    {
        let keys = (UInt16(0)...50).filter { KeyKind(keyCode: $0) == .character }.map { KeyStroke($0) }
        // Two-letter starts, so the spell checker's short completion lists still add up to a broad
        // sample, visited in a fixed scattered order rather than alphabetically.
        var prefixes: Set<String> = []
        for first in keys {
            for second in keys {
                let text = keyboard.text(for: [first, second])
                if text.count == 2, text.allSatisfy(\.isLetter) { prefixes.insert(text.lowercased()) }
            }
        }
        let order = prefixes.sorted { scatter($0) < scatter($1) }
        var seen: Set<String> = []
        var words: [(String, [KeyStroke])] = []
        for prefix in order where words.count < count {
            // A couple of words per start: enough spread that no one prefix dominates.
            var taken = 0
            for word in lexicon.words(startingWith: prefix, language: keyboard.baseLanguage) {
                guard taken < 2, word.count >= 2, !seen.contains(word), word.allSatisfy(\.isLetter),
                    split.contains(word), let strokes = keyboard.strokes(for: word),
                    keyboard.text(for: strokes) == word
                else { continue }
                seen.insert(word)
                words.append((word, strokes))
                taken += 1
            }
        }
        return Array(words.prefix(count))
    }

    private static func scatter(_ text: String) -> UInt64 {
        text.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01b3 }
    }

    public var table: String {
        var lines = ["Typed on the right keyboard (changed anyway is a false fix):"]
        for source in sources {
            let rate = source.words == 0 ? 0 : 100 * Double(source.falseFixes) / Double(source.words)
            lines.append(
                String(
                    format: "  %@  %d words, %d false fixes (%.1f%%)", source.keyboard, source.words,
                    source.falseFixes, rate)
                    + (source.examples.isEmpty ? "" : "  e.g. " + source.examples.joined(separator: ", ")))
        }
        lines.append(
            "Typed on the wrong keyboard (fixed back is the goal; identical readings cannot be told apart):")
        for pair in pairs {
            let telling = pair.words - pair.identical
            let rate = telling == 0 ? 0 : 100 * Double(pair.fixed) / Double(telling)
            lines.append(
                String(
                    format:
                        "  meant %@, typed on %@: %d/%d fixed (%.1f%%), %d to a third keyboard, %d identical",
                    pair.meant, pair.typedOn, pair.fixed, telling, rate, pair.misfixed, pair.identical)
                    + (pair.missed.isEmpty ? "" : "  missed " + pair.missed.joined(separator: ", ")))
        }
        if !skipped.isEmpty {
            lines.append("No dictionary to sample words from: " + skipped.joined(separator: ", "))
        }
        lines.append(String(format: "%.2f ms to judge a word", millisecondsPerWord))
        return lines.joined(separator: "\n")
    }
}
