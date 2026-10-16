import Foundation

/// What happened each day, for the menu: words written per keyboard, fixes by hour, and fixes
/// taken back. Counts only, never the words themselves, and only the last month.
public struct UsageStats: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable {
        /// The local calendar day, as yyyy-MM-dd.
        public var date: String
        /// Words written on each keyboard, after any fix.
        public var words: [String: Int] = [:]
        /// Words written in each app.
        public var apps: [String: Int] = [:]
        public var fixes: Int = 0
        public var undone: Int = 0
        public var hourlyFixes = [Int](repeating: 0, count: 24)

        /// A day with nothing recorded yet.
        public init(date: String) {
            self.date = date
        }

        public var totalWords: Int { words.values.reduce(0, +) }
    }

    public private(set) var days: [Day] = []
    private static let kept = 31

    public init() {}

    public mutating func recordWord(on keyboard: String, in app: String?, at time: Date) {
        update(time) { day in
            day.words[keyboard, default: 0] += 1
            if let app { day.apps[app, default: 0] += 1 }
        }
    }

    public mutating func recordFix(at time: Date) {
        let hour = Calendar.current.component(.hour, from: time)
        update(time) { day in
            day.fixes += 1
            day.hourlyFixes[hour] += 1
        }
    }

    public mutating func recordUndo(at time: Date) {
        update(time) { $0.undone += 1 }
    }

    public func day(_ time: Date) -> Day {
        let key = Self.key(time)
        return days.last(where: { $0.date == key }) ?? Day(date: key)
    }

    /// The last `count` days ending with `time`'s, oldest first, quiet days included.
    public func last(_ count: Int, endingAt time: Date) -> [Day] {
        (0..<count).reversed().map { back in
            day(Calendar.current.date(byAdding: .day, value: -back, to: time) ?? time)
        }
    }

    private mutating func update(_ time: Date, _ change: (inout Day) -> Void) {
        let key = Self.key(time)
        if let index = days.lastIndex(where: { $0.date == key }) {
            change(&days[index])
            return
        }
        var day = Day(date: key)
        change(&day)
        days.append(day)
        days.sort { $0.date < $1.date }
        days.removeFirst(max(0, days.count - Self.kept))
    }

    private static func key(_ time: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: time)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
