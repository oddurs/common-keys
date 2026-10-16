import Foundation

/// Whether a Latin reading could be a word spelled for a converting input method. These keyboards
/// produce text the user picks, so the only evidence available is the shape of the reading itself.
public struct Phonotactics: Sendable {
    public let name: String
    private let pattern: String

    /// Hepburn and kunrei romaji, as Japanese input methods accept them.
    public static let romaji = Phonotactics(
        name: "romaji",
        pattern:
            #"^(?:(?:ky|gy|sh|sy|ch|cy|ty|ts|ny|hy|by|py|my|ry|dy|zy|j|f|[kgsztdnhbpmyrwv])?[aiueo]|n(?![aiueoy])|nn|xtu|ltu|([kgsztdhbpmrjfc])(?=\1)|t(?=ch))+$"#
    )

    /// Toneless Hanyu Pinyin syllables, as Chinese Pinyin input methods accept them.
    public static let pinyin = Phonotactics(
        name: "pinyin",
        pattern:
            #"^(?:(?:zh|ch|sh|[bpmfdtnlgkhjqxrzcsyw])?(?:iang|iong|uang|ang|eng|ing|ong|ian|iao|uai|uan|ai|ao|an|ei|en|er|ia|ie|in|iu|ou|ua|ui|un|uo|ue|ve|a|o|e|i|u|v))+$"#
    )

    public func accepts(_ reading: String) -> Bool {
        reading.lowercased().range(of: pattern, options: .regularExpression) != nil
    }
}
