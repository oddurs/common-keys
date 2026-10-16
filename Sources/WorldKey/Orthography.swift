import Foundation

/// Spelling facts that hold for every word in a script, so they judge a reading even in a language
/// with no dictionary. Typing on the wrong layout breaks them constantly.
enum Orthography {
    /// Scripts by code point range, enough to tell when one word mixes two of them.
    private static let scripts: [(range: ClosedRange<UInt32>, name: String)] = [
        (0x0041...0x024F, "Latin"), (0x1E00...0x1EFF, "Latin"), (0x0370...0x03FF, "Greek"),
        (0x1F00...0x1FFF, "Greek"), (0x0400...0x052F, "Cyrillic"), (0x0530...0x058F, "Armenian"),
        (0x0590...0x05FF, "Hebrew"), (0x0600...0x06FF, "Arabic"), (0x0750...0x077F, "Arabic"),
        (0x0700...0x074F, "Syriac"), (0x0780...0x07BF, "Thaana"), (0x0900...0x097F, "Devanagari"),
        (0x0980...0x09FF, "Bengali"), (0x0A00...0x0A7F, "Gurmukhi"), (0x0A80...0x0AFF, "Gujarati"),
        (0x0B00...0x0B7F, "Oriya"), (0x0B80...0x0BFF, "Tamil"), (0x0C00...0x0C7F, "Telugu"),
        (0x0C80...0x0CFF, "Kannada"), (0x0D00...0x0D7F, "Malayalam"), (0x0D80...0x0DFF, "Sinhala"),
        (0x0E00...0x0E7F, "Thai"), (0x0E80...0x0EFF, "Lao"), (0x0F00...0x0FFF, "Tibetan"),
        (0x1000...0x109F, "Myanmar"), (0x10A0...0x10FF, "Georgian"), (0x1100...0x11FF, "Hangul"),
        (0x3130...0x318F, "Hangul"), (0xAC00...0xD7AF, "Hangul"), (0x1200...0x139F, "Ethiopic"),
        (0x13A0...0x13FF, "Cherokee"), (0x1400...0x167F, "Canadian"), (0x1780...0x17FF, "Khmer"),
        (0x1800...0x18AF, "Mongolian"), (0x3040...0x30FF, "Kana"), (0x4E00...0x9FFF, "Han"),
    ]

    static func script(of scalar: Unicode.Scalar) -> String? {
        // Marks and punctuation belong to whatever they sit in.
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return nil
        default: break
        }
        return scripts.first { $0.range.contains(scalar.value) }?.name
    }

    /// The dominant script of a reading, used to tell same-script choices from cross-script ones.
    static func script(of text: some StringProtocol) -> String? {
        text.unicodeScalars.lazy.compactMap(script(of:)).first
    }

    /// How badly `word` breaks the rules of its script. Zero for a well-formed word.
    static func penalty(_ word: Substring) -> Double {
        let scalars = Array(word.unicodeScalars)
        guard let first = scalars.first else { return 0 }
        var penalty = 0.0

        // No script starts a word with a combining mark: a vowel sign, virama or tone mark.
        if isMark(first) { penalty += 3 }

        // Hebrew final forms and Greek final sigma only end words.
        for (index, scalar) in scalars.enumerated().dropLast()
        where finalForms.contains(scalar.value) && isLetter(scalars[index + 1]) {
            penalty += 3
            break
        }

        // Thai and Lao prefixed vowels must come before a consonant.
        if let last = scalars.last,
            (0x0E40...0x0E44).contains(last.value) || (0x0EC0...0x0EC4).contains(last.value)
        {
            penalty += 2
        }

        // Korean typed on the right layout composes into syllables; leftover vowel letters mean the
        // keys were meant for some other layout. Consonant runs such as ㅋㅋㅋ are real usage.
        if scalars.contains(where: { (0x314F...0x3163).contains($0.value) }) { penalty += 2 }

        // One word, one script.
        if Set(scalars.compactMap(script(of:))).count > 1 { penalty += 2 }
        return penalty
    }

    private static let finalForms: Set<UInt32> = [0x05DA, 0x05DD, 0x05DF, 0x05E3, 0x05E5, 0x03C2]

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic && !isMark(scalar)
    }
}
