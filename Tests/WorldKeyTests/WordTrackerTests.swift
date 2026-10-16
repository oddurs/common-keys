import Foundation
import Testing

@testable import WorldKey

struct WordTrackerTests {
    let space = KeyStroke(49)
    let start = Date(timeIntervalSince1970: 0)

    @Test func endingAWordRemembersIt() {
        var tracker = WordTracker(layoutID: "us")
        tracker.type(keys("pat"))
        #expect(tracker.end(with: space, now: start) == nil)
        #expect(tracker.previous?.word == TrackedWord(strokes: keys("pat"), layoutID: "us"))
        #expect(tracker.currentWord == nil)
    }

    @Test func eraseSwitchAndRetypeIsLearned() {
        var tracker = WordTracker(layoutID: "us")
        tracker.type(keys("/etta"))
        _ = tracker.end(with: space, now: start)
        // The space, then the five letters.
        for _ in 0...5 { tracker.backspace(wholeWord: false, now: start) }
        #expect(tracker.currentWord == nil)
        tracker.setLayout("is")
        tracker.type(keys("/etta"))
        let retype = tracker.end(with: space, now: start.addingTimeInterval(3))
        #expect(retype == Retype(strokes: keys("/etta"), from: "us", to: "is"))
    }

    @Test func retypingInTheSameLayoutIsJustATypo() {
        var tracker = WordTracker(layoutID: "us")
        tracker.type(keys("teh"))
        tracker.backspace(wholeWord: true, now: start)
        tracker.type(keys("teh"))
        #expect(tracker.end(with: space, now: start) == nil)
    }

    @Test func staleErasuresAreNotEvidence() {
        var tracker = WordTracker(layoutID: "us")
        tracker.type(keys("/etta"))
        tracker.backspace(wholeWord: true, now: start)
        tracker.setLayout("is")
        tracker.type(keys("/etta"))
        #expect(tracker.end(with: space, now: start.addingTimeInterval(120)) == nil)
    }

    @Test func switchingMidWordStartsOver() {
        var tracker = WordTracker(layoutID: "us")
        tracker.type(keys("/e"))
        tracker.setLayout("is")
        tracker.type(keys("tta"))
        #expect(tracker.currentWord == TrackedWord(strokes: keys("tta"), layoutID: "is"))
    }

    @Test func resetForgetsTheCursorContext() {
        var tracker = WordTracker(layoutID: "us")
        tracker.type(keys("pat"))
        _ = tracker.end(with: space, now: start)
        tracker.reset()
        tracker.backspace(wholeWord: false, now: start)
        #expect(tracker.previous == nil)
        #expect(tracker.currentWord == nil)
    }

    @Test func keyKinds() {
        #expect(KeyKind(keyCode: 44) == .character)  // `/`, which is þ on Icelandic
        #expect(KeyKind(keyCode: 49) == .boundary)
        #expect(KeyKind(keyCode: 51) == .backspace)
        #expect(KeyKind(keyCode: 123) == .other)  // left arrow
    }
}

extension WordTracker {
    fileprivate mutating func type(_ strokes: [KeyStroke]) {
        for stroke in strokes { type(stroke) }
    }
}
