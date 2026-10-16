import Foundation
import Testing
import WorldKey

struct UsageStatsTests {
    let noon = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 12))!

    @Test func countsWordsFixesAndUndos() {
        var stats = UsageStats()
        stats.recordWord(on: "us", in: "mail", at: noon)
        stats.recordWord(on: "is", in: "mail", at: noon)
        stats.recordWord(on: "is", in: "notes", at: noon)
        stats.recordFix(at: noon)
        stats.recordFix(at: noon.addingTimeInterval(3600))
        stats.recordUndo(at: noon)
        let today = stats.day(noon)
        #expect(today.words == ["us": 1, "is": 2])
        #expect(today.apps == ["mail": 2, "notes": 1])
        #expect(today.totalWords == 3)
        #expect(today.fixes == 2)
        #expect(today.undone == 1)
        #expect(today.hourlyFixes[12] == 1)
        #expect(today.hourlyFixes[13] == 1)
    }

    @Test func daysAreSeparateAndQuietDaysAreEmpty() {
        var stats = UsageStats()
        let yesterday = noon.addingTimeInterval(-86_400)
        stats.recordFix(at: yesterday)
        stats.recordFix(at: noon)
        stats.recordFix(at: noon)
        #expect(stats.last(3, endingAt: noon).map(\.fixes) == [0, 1, 2])
    }

    @Test func keepsAMonth() {
        var stats = UsageStats()
        for back in 0..<60 { stats.recordFix(at: noon.addingTimeInterval(Double(-back) * 86_400)) }
        #expect(stats.days.count == 31)
        #expect(stats.days.last?.fixes == 1)
    }

    @Test func survivesARoundTrip() throws {
        var stats = UsageStats()
        stats.recordWord(on: "us", in: nil, at: noon)
        stats.recordFix(at: noon)
        let data = try JSONEncoder().encode(stats)
        #expect(try JSONDecoder().decode(UsageStats.self, from: data) == stats)
    }
}
