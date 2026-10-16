import Foundation

public struct Decision: Equatable, Sendable {
    public let targetID: String
    public let original: String
    public let replacement: String
    /// Some of the gain, or all of it, came from what the user taught us.
    public let learned: Bool
    /// How much more plausible the replacement reads than the original.
    public let gain: Double
}

/// Decides which keyboard a run of keys was meant for, by reading the keys on every candidate
/// keyboard and weighing each reading on what is known about its language.
@MainActor
public struct Detector {
    /// How much more plausible another reading must be before acting without being asked.
    public var threshold: Double
    public var minLength: Int
    public var weights: Weights

    /// Weights default to the fitted ones; `.hand` is the rule-tuned baseline they are gated against.
    public init(threshold: Double? = nil, minLength: Int = 2, weights: Weights = .trained) {
        self.threshold = threshold ?? weights.threshold
        self.minLength = minLength
        self.weights = weights
    }

    /// The fix to apply when a word ends, if any.
    public func decide(
        _ strokes: [KeyStroke], typedIn current: any Keyboard, candidates: [any Keyboard], memory: Memory,
        lexicon: some Lexicon
    ) -> Decision? {
        // What converting input methods put on screen is the user's pick; there is nothing to read back.
        guard strokes.count >= minLength, current.kind != .converting else { return nil }
        if memory.exceptions[strokes.signature]?.layoutID == current.id { return nil }
        if let learned = learned(strokes, typedIn: current, candidates: candidates, memory: memory) {
            return learned
        }
        // Digits are not words either, unless another keyboard reads those keys as letters: the
        // French number row types é, è and à.
        guard !Self.looksLikeAddress(current.text(for: strokes)) else { return nil }
        return alternatives(
            strokes, typedIn: current, candidates: candidates, memory: memory, lexicon: lexicon
        )
        .first {
            $0.gain >= threshold + Self.margin(for: $0, among: candidates)
                && !Self.looksLikeMachineText($0.replacement)
        }
    }

    /// The fix to apply while the word is still being typed: only when no word of the current
    /// language starts this way and many words of another do.
    public func decidePrefix(
        _ strokes: [KeyStroke], typedIn current: any Keyboard, candidates: [any Keyboard], memory: Memory,
        lexicon: some Lexicon
    ) -> Decision? {
        guard strokes.count >= max(minLength, 3), current.kind == .direct else { return nil }
        if memory.exceptions[strokes.signature]?.layoutID == current.id { return nil }
        let original = current.text(for: strokes)
        guard !Self.looksLikeMachineText(original),
            lexicon.startsWord(Scorer.core(original), language: current.language) == false
        else { return nil }
        for target in candidates where target.id != current.id && target.kind != .converting {
            let text = target.text(for: strokes)
            guard text != original, Orthography.penalty(Scorer.core(text)[...]) == 0,
                lexicon.startsWord(Scorer.core(text), language: target.language) == true
            else { continue }
            return Decision(
                targetID: target.id, original: original, replacement: text, learned: false,
                gain: threshold + 1)
        }
        return nil
    }

    /// Every other reading of the keys, most plausible first. The user asked, so no threshold.
    public func alternatives(
        _ strokes: [KeyStroke], typedIn current: any Keyboard, candidates: [any Keyboard], memory: Memory,
        lexicon: some Lexicon
    ) -> [Decision] {
        let original = current.text(for: strokes)
        let base = Scorer.features(original, on: current, lexicon: lexicon)
        return candidates.compactMap { keyboard -> Decision? in
            guard keyboard.id != current.id else { return nil }
            let text = keyboard.text(for: strokes)
            // A converting method's reading is the same letters; what changes is who gets them.
            guard !text.isEmpty, text != original || keyboard.kind == .converting else { return nil }
            let evidence = evidence(
                strokes, original: original, base: base, typedIn: current, readAs: text, on: keyboard, memory: memory,
                lexicon: lexicon)
            return Decision(
                targetID: keyboard.id, original: original, replacement: text, learned: evidence[.taught] > 0,
                gain: weights.score(evidence))
        }
        .sorted { $0.gain > $1.gain }
    }

    /// The evidence that keys typed on `current` were meant for `candidate`: each feature of the
    /// candidate's reading less the same feature of the reading on screen, plus what the pair adds.
    public func evidence(
        _ strokes: [KeyStroke], typedIn current: any Keyboard, meantFor candidate: any Keyboard, memory: Memory,
        lexicon: some Lexicon
    ) -> FeatureVector {
        let original = current.text(for: strokes)
        return evidence(
            strokes, original: original, base: Scorer.features(original, on: current, lexicon: lexicon),
            typedIn: current, readAs: candidate.text(for: strokes), on: candidate, memory: memory, lexicon: lexicon)
    }

    private func evidence(
        _ strokes: [KeyStroke], original: String, base: FeatureVector, typedIn current: any Keyboard,
        readAs text: String, on candidate: any Keyboard, memory: Memory, lexicon: some Lexicon
    ) -> FeatureVector {
        let meant = Scorer.features(text, on: candidate, lexicon: lexicon)
        var evidence = meant - base
        evidence[.bothKnown] = base[.knownWord] * meant[.knownWord]
        evidence[.taught] = memory.boost(strokes, from: current.id, to: candidate.id)
        evidence[.recognized] = Scorer.recognition(
            original, on: current, against: text, on: candidate, lexicon: lexicon)
        if let shown = lexicon.typicality(Scorer.core(original), on: current),
            let meant = lexicon.typicality(Scorer.core(text), on: candidate)
        {
            // Clamped: a reading full of characters a language never uses is noise either way.
            evidence[.shownTypicality] = max(-5, shown)
            evidence[.meantTypicality] = max(-5, meant)
        }
        return evidence
    }

    /// The keyboard whose reading of the keys is clearly best among all candidates, the one it was
    /// typed on included. This says which language a word was meant in, even when every keyboard
    /// types it the same. Nil when the readings are too close to call.
    public func clearestReading(_ strokes: [KeyStroke], candidates: [any Keyboard], lexicon: some Lexicon)
        -> String?
    {
        guard strokes.count >= max(minLength, 2), candidates.count > 1 else { return nil }
        let scored = candidates.map { keyboard in
            let text = keyboard.text(for: strokes)
            let score = weights.score(Scorer.features(text, on: keyboard, lexicon: lexicon))
            return (id: keyboard.id, text: text, score: score)
        }
        .sorted { $0.score > $1.score }
        guard !Self.looksLikeMachineText(scored[0].text), scored[0].score - scored[1].score >= 1 else {
            return nil
        }
        return scored[0].id
    }

    /// Extra margin before acting on our own: a converting input method takes over the keys from
    /// then on, so a wrong guess costs more than a wrong letter.
    private static func margin(for decision: Decision, among candidates: [any Keyboard]) -> Double {
        candidates.first { $0.id == decision.targetID }?.kind == .converting ? 1 : 0
    }

    private func learned(
        _ strokes: [KeyStroke], typedIn current: any Keyboard, candidates: [any Keyboard], memory: Memory
    ) -> Decision? {
        guard let word = memory.words[strokes.signature], word.to != current.id,
            let target = candidates.first(where: { $0.id == word.to })
        else { return nil }
        let original = current.text(for: strokes)
        let replacement = target.text(for: strokes)
        guard replacement != original || target.kind == .converting else { return nil }
        return Decision(
            targetID: target.id, original: original, replacement: replacement, learned: true, gain: .infinity)
    }

    /// Paths, addresses and anything with digits are not words in any language.
    static func looksLikeMachineText(_ text: String) -> Bool {
        text.contains(where: \.isNumber) || looksLikeAddress(text)
    }

    /// Paths, links and addresses: left alone however another keyboard reads them.
    static func looksLikeAddress(_ text: String) -> Bool {
        text.contains("://") || text.contains("@") || text.filter { $0 == "/" }.count > 1
    }
}

/// The evidence about a reading as a word of its keyboard's language. Weights turn it into a score;
/// only differences between readings of the same keys matter.
@MainActor
enum Scorer {
    private static let leading: Set<Character> = ["(", "\"", "'", "«", "“", "‘", "„", "¿", "¡"]
    private static let trailing: Set<Character> = [
        ".", ",", "!", "?", ":", ";", ")", "\"", "'", "»", "”", "’", "…", "،", "؟", "。", "、",
    ]
    private static let joiners: Set<Character> = ["'", "’", "-", "\u{200C}", "\u{200D}"]

    /// The word inside its punctuation.
    static func core(_ text: String) -> String {
        String(trim(text).core)
    }

    private static func trim(_ text: String) -> (core: Substring, trailing: Int) {
        var core = Substring(text)
        while let first = core.first, leading.contains(first) { core = core.dropFirst() }
        var trailingCount = 0
        while let last = core.last, trailing.contains(last) {
            core = core.dropLast()
            trailingCount += 1
        }
        return (core, trailingCount)
    }

    /// The evidence about one reading of the keys, on the keyboard that reads them that way.
    static func features(_ text: String, on keyboard: any Keyboard, lexicon: some Lexicon) -> FeatureVector {
        guard keyboard.kind == .converting else {
            return features(text, language: keyboard.baseLanguage, lexicon: lexicon)
        }
        // Only the shape of the reading says anything, and the longer a reading keeps to the
        // language's syllables, the less likely that is chance. An unknown method never wins alone.
        var features = FeatureVector()
        guard let phonotactics = (keyboard as? ConvertingKeyboard)?.phonotactics, text.count >= 4 else {
            features[.unmodeledMethod] = 1
            return features
        }
        if phonotactics.accepts(text) {
            features[.readingAccepted] = 1
            features[.readingLength] = min(0.25 * Double(text.count - 4), 2)
        } else {
            features[.readingRejected] = 1
        }
        return features
    }

    /// The recognizer's say between two readings in one script, where it can tell languages apart.
    /// Across scripts it only recognizes the script, which says nothing, so it stays out.
    static func recognition(
        _ original: String, on current: any Keyboard, against text: String, on candidate: any Keyboard,
        lexicon: some Lexicon
    ) -> Double {
        guard current.kind != .converting, candidate.kind != .converting,
            current.baseLanguage != candidate.baseLanguage,
            Orthography.script(of: original) == Orthography.script(of: text)
        else { return 0 }
        let languages = [current.baseLanguage, candidate.baseLanguage]
        let mine = lexicon.languageLikelihood(core(original), among: languages)[current.baseLanguage] ?? 0
        let theirs = lexicon.languageLikelihood(core(text), among: languages)[candidate.baseLanguage] ?? 0
        return theirs - mine
    }

    static func features(_ text: String, language: String, lexicon: some Lexicon) -> FeatureVector {
        let (core, trailingCount) = trim(text)
        let alphabet = lexicon.alphabet(for: language)
        var features = FeatureVector()
        features[.trailingPunctuation] = Double(trailingCount)
        features[.orthography] = Orthography.penalty(core)
        var clean = true
        var letters = 0
        for character in core where !joiners.contains(character) && !character.isNumber {
            if character.isLetter || character.unicodeScalars.allSatisfy(\.properties.isAlphabetic) {
                letters += 1
                if let alphabet, !character.lowercased().unicodeScalars.allSatisfy(alphabet.contains) {
                    features[.foreignLetters] += 1
                    clean = false
                }
            } else {
                // A symbol inside a word is the strongest sign of the wrong layout: `/etta` for `þetta`.
                features[.symbols] += 1
                clean = false
            }
        }
        if clean && letters > 0 { features[.clean] = 1 }
        // Spell checkers read "x'…" as an elision, like "l'homme", and accept it whenever the rest is
        // a word. That makes "h'us", which is "hús" on the wrong layout, pass as English.
        let elided = core.count > 2 && joiners.contains(core[core.index(after: core.startIndex)])
        if core.count >= 2, !elided {
            switch lexicon.isWord(String(core), language: language) {
            case true?: features[.knownWord] = 1
            case false?: features[.unknownWord] = 1
            case nil:
                // A reading has to earn its place some other way, such as a shipped word list.
                features[.noDictionary] = 1
                if lexicon.isListed(String(core), language: language) { features[.listedWord] = 1 }
            }
        }
        return features
    }
}
