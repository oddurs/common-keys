import Foundation
import Testing
import WorldKey

struct RecentLayoutsTests {
    let start = Date(timeIntervalSince1970: 0)

    @Test func eachAppKeepsItsOwnLayout() {
        var recent = RecentLayouts()
        recent.note("is", in: "slack", at: start)
        recent.note("us", in: "mail", at: start)
        #expect(recent.layout(in: "slack", now: start, within: 60) == "is")
        #expect(recent.layout(in: "mail", now: start, within: 60) == "us")
        #expect(recent.layout(in: "notes", now: start, within: 60) == nil)
    }

    @Test func oldVisitsAreForgotten() {
        var recent = RecentLayouts()
        recent.note("is", in: "slack", at: start)
        #expect(recent.layout(in: "slack", now: start.addingTimeInterval(3600), within: 3600) == "is")
        #expect(recent.layout(in: "slack", now: start.addingTimeInterval(3601), within: 3600) == nil)
    }

    @Test func latestUseWins() {
        var recent = RecentLayouts()
        recent.note("is", in: "slack", at: start)
        recent.note("us", in: "slack", at: start.addingTimeInterval(5))
        #expect(recent.layout(in: "slack", now: start.addingTimeInterval(10), within: 60) == "us")
    }

    @Test func choiceRanksRecentThenPinnedThenUsualThenPreferred() {
        #expect(AppLayoutChoice.choose(recent: "is", pinned: "us", usual: "us", preferred: "us") == "is")
        #expect(AppLayoutChoice.choose(recent: nil, pinned: "is", usual: "us", preferred: "us") == "is")
        #expect(AppLayoutChoice.choose(recent: nil, pinned: nil, usual: "is", preferred: "us") == "is")
        #expect(AppLayoutChoice.choose(recent: nil, pinned: nil, usual: nil, preferred: "us") == "us")
        #expect(AppLayoutChoice.choose(recent: nil, pinned: nil, usual: nil, preferred: nil) == nil)
    }
}
