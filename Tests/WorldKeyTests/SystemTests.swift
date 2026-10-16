import Testing
import WorldKey

/// The real layouts, input methods and spell checker on this Mac.
@MainActor
struct SystemTests {
    let us = InputSources.keyboard("com.apple.keylayout.US")!
    let icelandic = InputSources.keyboard("com.apple.keylayout.Icelandic")!
    let russian = InputSources.keyboard("com.apple.keylayout.Russian")!
    let hebrew = InputSources.keyboard("com.apple.keylayout.Hebrew")!
    let greek = InputSources.keyboard("com.apple.keylayout.Greek")!
    let korean = InputSources.keyboard("com.apple.inputmethod.Korean.2SetKorean")!
    let japanese = InputSources.keyboard("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese")!
    let lexicon = SystemLexicon()

    func decide(_ keys: String, on current: any Keyboard, with other: any Keyboard) -> Decision? {
        Detector().decide(
            WorldKeyTests.keys(keys), typedIn: current, candidates: [current, other], memory: Memory(),
            lexicon: lexicon)
    }

    @Test func translatesWithSystemTables() {
        #expect(us.text(for: keys("/etta")) == "/etta")
        #expect(icelandic.text(for: keys("/etta")) == "þetta")
        #expect(icelandic.text(for: [KeyStroke(44, shift: true)] + keys("a[")) == "Það")
        #expect(russian.text(for: keys("ghbdtn")) == "привет")
    }

    @Test func deadKeysCompose() {
        // `'` is the acute dead key on Icelandic.
        #expect(icelandic.text(for: keys("f'a")) == "fá")
        #expect(icelandic.text(for: keys("don't")) == "don´t")
        #expect(icelandic.text(for: keys("dogs'")) == "dogs´")
    }

    @Test func inputMethodsHaveModels() {
        #expect(korean.kind == .composing)
        #expect(korean.text(for: keys("dkssudgktpdy")) == "안녕하세요")
        #expect(japanese.kind == .converting)
        #expect(japanese.text(for: keys("konnichiha")) == "konnichiha")
    }

    @Test func everyInstalledLayoutTypesBackWhatItReads() {
        // Reading keys and finding keys for text are inverses on every layout macOS ships.
        var failures: [String] = []
        for keyboard in InputSources.installed() where keyboard.kind == .direct {
            let sample = keys("qwertyuiopasdfghjklzxcvbnm")
            let text = keyboard.text(for: sample)
            guard let strokes = keyboard.strokes(for: text), keyboard.text(for: strokes) == text else {
                failures.append(keyboard.id)
                continue
            }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test(arguments: [
        ("/etta", "þetta"), ("/a[", "það"), ("f'a", "fá"), (";tlar", "ætlar"), ("h'us", "hús"),
        ("r'um", "rúm"),
    ])
    func icelandicOnUSIsFixed(typed: String, meant: String) {
        #expect(decide(typed, on: us, with: icelandic)?.replacement == meant)
    }

    @Test(arguments: ["don't", "it's", "you're"])
    func englishOnIcelandicIsFixed(word: String) {
        #expect(decide(word, on: icelandic, with: us)?.replacement == word)
    }

    @Test(arguments: ["hello", "don't", "the", "world;", "and,"])
    func correctEnglishIsLeftAlone(word: String) {
        #expect(decide(word, on: us, with: icelandic) == nil)
    }

    @Test(arguments: ["/etta", "/a[", "hallo"])
    func correctIcelandicIsLeftAlone(typed: String) {
        #expect(decide(typed, on: icelandic, with: us) == nil)
    }

    /// A fresh CI runner can answer Russian spelling queries with no completions at first (#3).
    /// Waiting keeps these tests about the detector rather than the spell server's start-up.
    func waitForRussianDictionary() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        var polls = 0
        while SystemLexicon().startsWord("прив", language: "ru") != true {
            polls += 1
            guard clock.now - start < .seconds(60) else {
                Issue.record("the Russian spelling dictionary gave no completions for 60 seconds")
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        if polls > 0 {
            print("waited \(clock.now - start) for the Russian spelling dictionary")
        }
    }

    @Test func russianOnUSIsFixed() async throws {
        try await waitForRussianDictionary()
        #expect(decide("ghbdtn", on: us, with: russian)?.replacement == "привет")
    }

    @Test func acrossScripts() {
        #expect(decide("hello", on: russian, with: us)?.replacement == "hello")
        #expect(decide("hello", on: us, with: russian) == nil)
        #expect(decide("akuo", on: us, with: hebrew)?.replacement == "שלום")
        #expect(decide("today", on: hebrew, with: us)?.replacement == "today")
        #expect(decide("today", on: greek, with: us)?.replacement == "today")
        #expect(decide("dkssud", on: us, with: korean)?.replacement == "안녕")
        #expect(decide("hello", on: korean, with: us)?.replacement == "hello")
    }

    @Test func romajiGoesToTheInputMethod() {
        let decision = decide("konnichiha", on: us, with: japanese)
        #expect(decision?.targetID == japanese.id)
        #expect(decide("make", on: us, with: japanese) == nil)
    }

    @Test func fixesAsYouTypeOnlyWhenNoWordStartsThatWay() async throws {
        try await waitForRussianDictionary()
        let detector = Detector()
        let early = detector.decidePrefix(
            keys("ghbd"), typedIn: us, candidates: [us, russian], memory: Memory(), lexicon: lexicon)
        #expect(early?.replacement == "прив")
        #expect(
            detector.decidePrefix(
                keys("hell"), typedIn: us, candidates: [us, russian], memory: Memory(), lexicon: lexicon)
                == nil)
    }
}

/// A small run of the accuracy evaluation, as a gate: correctly typed words stay put, and words
/// typed on the wrong keyboard come back.
@MainActor
struct AccuracyTests {
    @Test(arguments: [
        ["com.apple.keylayout.US", "com.apple.keylayout.Icelandic"],
        ["com.apple.keylayout.US", "com.apple.keylayout.Russian"],
        ["com.apple.keylayout.US", "com.apple.inputmethod.Korean.2SetKorean"],
    ])
    func dictionaryWords(ids: [String]) {
        let keyboards = ids.compactMap(InputSources.keyboard)
        let report = Evaluation.run(keyboards, words: 40, lexicon: SystemLexicon())
        for source in report.sources {
            #expect(source.falseFixes == 0, "\(source.keyboard): \(source.examples)")
        }
        for pair in report.pairs where pair.words > pair.identical {
            let rate = Double(pair.fixed) / Double(pair.words - pair.identical)
            #expect(rate >= 0.9, "\(pair.meant) on \(pair.typedOn): \(pair.missed)")
        }
    }
}
