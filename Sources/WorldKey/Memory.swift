/// What the user has taught us: words they meant in another layout, words to leave alone,
/// and which keys they tend to mix up.
public struct Memory: Codable, Equatable, Sendable {
    public struct Word: Codable, Equatable, Sendable {
        public var strokes: [KeyStroke]
        public var from: String
        public var to: String
        public var count: Int
    }

    public struct Exception: Codable, Equatable, Sendable {
        public var strokes: [KeyStroke]
        public var layoutID: String
    }

    /// A key the user pressed in `from` while meaning `to`.
    public struct Confusion: Codable, Hashable, Sendable {
        public var from: String
        public var to: String
        public var keyCode: UInt16
        public var count: Int
    }

    public var words: [String: Word] = [:]
    public var exceptions: [String: Exception] = [:]
    public var confusions: [Confusion] = []
    /// Words written per layout in each app, by bundle identifier.
    public var apps: [String: [String: Double]] = [:]
    /// Words the user typed and kept, counted by a salted hash of keyboard and keys: never the words.
    public var kept: [String: Double] = [:]
    /// Random per Mac, so the hashes in `kept` mean nothing anywhere else.
    public var salt: UInt64 = .random(in: .min ... .max)
    /// The user's own adjustments to the shipped weights, learned from their corrections.
    public var adjustments: [Feature: Double] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case words, exceptions, confusions, apps, kept, salt, adjustments
    }

    /// Every field is optional so memory from an older version still loads.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        words = try container.decodeIfPresent([String: Word].self, forKey: .words) ?? [:]
        exceptions = try container.decodeIfPresent([String: Exception].self, forKey: .exceptions) ?? [:]
        confusions = try container.decodeIfPresent([Confusion].self, forKey: .confusions) ?? []
        apps = try container.decodeIfPresent([String: [String: Double]].self, forKey: .apps) ?? [:]
        kept = try container.decodeIfPresent([String: Double].self, forKey: .kept) ?? [:]
        salt = try container.decodeIfPresent(UInt64.self, forKey: .salt) ?? .random(in: .min ... .max)
        adjustments = try container.decodeIfPresent([Feature: Double].self, forKey: .adjustments) ?? [:]
    }

    public var isEmpty: Bool {
        words.isEmpty && exceptions.isEmpty && confusions.isEmpty && apps.isEmpty && kept.isEmpty
            && adjustments.isEmpty
    }

    /// Counts a word written in `layoutID` while `app` was in front.
    public mutating func recordUse(app: String, layoutID: String) {
        var counts = apps[app, default: [:]]
        counts[layoutID, default: 0] += 1
        // Halving keeps the habit current: older words fade instead of outvoting this week forever.
        if counts.values.reduce(0, +) > 200 { counts = counts.mapValues { $0 / 2 } }
        apps[app] = counts
    }

    /// The layout `app` is written in, once there is enough typing to be sure.
    public func usualLayout(app: String) -> (id: String, share: Double)? {
        guard let counts = apps[app] else { return nil }
        let total = counts.values.reduce(0, +)
        guard total >= 8, let best = counts.max(by: { $0.value < $1.value }) else { return nil }
        let share = best.value / total
        return share >= 0.6 ? (best.key, share) : nil
    }

    public mutating func learn(_ strokes: [KeyStroke], from: any Keyboard, to: any Keyboard) {
        let key = strokes.signature
        let count = words[key].map { $0.to == to.id ? $0.count + 1 : 1 } ?? 1
        words[key] = Word(strokes: strokes, from: from.id, to: to.id, count: count)
        exceptions[key] = nil
        for keyCode in Set(strokes.map(\.keyCode)) {
            let key = [KeyStroke(keyCode)]
            guard from.text(for: key) != to.text(for: key) else { continue }
            if let index = confusions.firstIndex(where: {
                $0.from == from.id && $0.to == to.id && $0.keyCode == keyCode
            }) {
                confusions[index].count += 1
            } else {
                confusions.append(Confusion(from: from.id, to: to.id, keyCode: keyCode, count: 1))
            }
        }
    }

    /// The user undid a fix: these keys mean what they said in `layoutID`.
    public mutating func keep(_ strokes: [KeyStroke], in layoutID: String) {
        let key = strokes.signature
        words[key] = nil
        exceptions[key] = Exception(strokes: strokes, layoutID: layoutID)
    }

    /// The user reverted a conversion they asked for, so it counts for one less.
    public mutating func unlearn(_ strokes: [KeyStroke]) {
        let key = strokes.signature
        guard var word = words[key] else { return }
        word.count -= 1
        words[key] = word.count > 0 ? word : nil
    }

    public mutating func forgetApp(_ app: String) {
        apps[app] = nil
    }

    public mutating func forget(_ signature: String) {
        words[signature] = nil
        exceptions[signature] = nil
    }

    /// Extra plausibility for reading `strokes` in `to`, earned by past mix-ups of the same keys.
    /// Capped below the default threshold so it tips close calls without deciding alone.
    public func boost(_ strokes: [KeyStroke], from: String, to: String) -> Double {
        let keyCodes = Set(strokes.map(\.keyCode))
        let total =
            confusions
            .filter { $0.from == from && $0.to == to && keyCodes.contains($0.keyCode) }
            .reduce(0) { $0 + min(1, 0.25 * Double($1.count)) }
        return min(total, 1.5)
    }
}
