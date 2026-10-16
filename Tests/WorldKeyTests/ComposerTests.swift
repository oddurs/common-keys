import Testing

@testable import WorldKey

struct HangulTests {
    let hangul = HangulComposer()

    @Test(arguments: [
        ("ㅇㅏㄴㄴㅕㅇ", "안녕"), ("ㅎㅏㄴㄱㅡㄹ", "한글"), ("ㄷㅏㄹㄱ", "닭"), ("ㄷㅏㄹㄱㅇㅣ", "닭이"),
        ("ㄱㅗㅏ", "과"), ("ㅇㅗㅐ", "왜"), ("ㅋㅋㅋ", "ㅋㅋㅋ"), ("ㅏ", "ㅏ"), ("ㄱㅏ ㄴㅏ", "가 나"),
        ("ㅇㅣㄹㄱㅇㅓ", "읽어"), ("ㄱㅏㅂㅅ", "값"),
    ])
    func composes(raw: String, text: String) {
        #expect(hangul.compose(raw) == text)
    }

    @Test(arguments: ["안녕하세요", "닭", "과자", "읽어", "값이"])
    func decomposesBackToTheSameKeys(text: String) {
        #expect(hangul.decompose(text).map(hangul.compose) == text)
    }

    @Test func erasesTheOpenSyllableKeyByKey() {
        // 안 is done; 녕 is still open, three keys deep.
        #expect(hangul.pendingErasures("ㅇㅏㄴㄴㅕㅇ") == 4)
        #expect(hangul.pendingErasures("ㄱㅗㅏ") == 3)
    }
}

struct VietnameseTests {
    let telex = VietnameseComposer(.telex)
    let vni = VietnameseComposer(.vni)

    @Test(arguments: [
        ("vieejt", "việt"), ("Vieejt Nam", "Việt Nam"), ("ddaay", "đây"), ("tieengs", "tiếng"),
        ("nguwowif", "người"), ("hoaf", "hoà"), ("cuar", "của"), ("quas", "quá"), ("giaf", "già"),
    ])
    func telexComposes(raw: String, text: String) {
        #expect(telex.compose(raw) == text)
    }

    @Test(arguments: [("vie65t", "việt"), ("d9a6y", "đây"), ("nguo72i", "người")])
    func vniComposes(raw: String, text: String) {
        #expect(vni.compose(raw) == text)
    }

    @Test(arguments: ["việt", "người", "đây", "tiếng"])
    func roundTrips(text: String) {
        #expect(telex.decompose(text).map(telex.compose) == text)
        #expect(vni.decompose(text).map(vni.compose) == text)
    }
}

struct PhonotacticsTests {
    @Test(arguments: ["konnichiha", "arigatou", "sushi", "kitte", "shinkansen", "matcha"])
    func romaji(reading: String) {
        #expect(Phonotactics.romaji.accepts(reading))
    }

    @Test(arguments: ["hello", "strength", "world"])
    func notRomaji(reading: String) {
        #expect(!Phonotactics.romaji.accepts(reading))
    }

    @Test(arguments: ["nihao", "zhongguo", "xiexie", "women"])
    func pinyin(reading: String) {
        #expect(Phonotactics.pinyin.accepts(reading))
    }

    @Test func notPinyin() {
        #expect(!Phonotactics.pinyin.accepts("strength"))
    }
}

struct OrthographyTests {
    @Test func wellFormedWordsPass() {
        for word in ["שלום", "καλός", "привет", "नमस्ते", "안녕", "ㅋㅋㅋ", "þetta"] {
            #expect(Orthography.penalty(word[...]) == 0, "\(word)")
        }
    }

    @Test func brokenWordsDoNot() {
        #expect(Orthography.penalty("אםגשט"[...]) > 0)  // final mem mid-word
        #expect(Orthography.penalty("λςκφ"[...]) > 0)  // final sigma mid-word
        #expect(Orthography.penalty("\u{94D}क"[...]) > 0)  // virama first
        #expect(Orthography.penalty("ㅗ디ㅣㅐ"[...]) > 0)  // loose vowels
        #expect(Orthography.penalty("hпривет"[...]) > 0)  // two scripts
    }
}
