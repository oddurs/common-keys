import Carbon
import Foundation

/// Every keyboard input source on this Mac, as a `Keyboard` the engine can reason about.
public enum InputSources {
    /// Sources the user has enabled, in menu order. Input methods with no model are left out.
    public static func enabled() -> [any Keyboard] {
        list(nil, includeAllInstalled: false).compactMap(keyboard(for:))
    }

    /// Every installed source with a model, enabled or not.
    ///
    /// Listing every installed source makes TIS count some input methods, such as Japanese and
    /// Ainu, as enabled for the rest of the process. Read `enabled()` before calling this.
    public static func installed() -> [any Keyboard] {
        list(nil, includeAllInstalled: true).compactMap(keyboard(for:))
    }

    public static func keyboard(_ id: String) -> (any Keyboard)? {
        list(id, includeAllInstalled: true).lazy.compactMap(keyboard(for:)).first
    }

    /// The layout shortcuts and Latin readings are spelled in: the current one if it types Latin,
    /// else the system's Latin fallback.
    public static func asciiCapable() -> LayoutKeyboard? {
        TISCopyCurrentASCIICapableKeyboardLayoutInputSource().flatMap {
            layoutKeyboard($0.takeRetainedValue())
        }
    }

    public static func currentID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return property(source, kTISPropertyInputSourceID)
    }

    @discardableResult
    public static func select(_ id: String) -> Bool {
        guard let source = list(id, includeAllInstalled: false).first else { return false }
        return TISSelectInputSource(source) == noErr
    }

    // MARK: Models

    private static func keyboard(for source: TISInputSource) -> (any Keyboard)? {
        guard let type: String = property(source, kTISPropertyInputSourceType) else { return nil }
        if type == kTISTypeKeyboardLayout as String { return layoutKeyboard(source) }
        guard type == kTISTypeKeyboardInputMode as String,
            let id: String = property(source, kTISPropertyInputSourceID),
            let name: String = property(source, kTISPropertyLocalizedName)
        else { return nil }
        let language = (property(source, kTISPropertyInputSourceLanguages) as [String]?)?.first ?? "und"
        return inputMethod(id: id, name: name, language: language)
    }

    private static func layoutKeyboard(_ source: TISInputSource) -> LayoutKeyboard? {
        guard let id: String = property(source, kTISPropertyInputSourceID),
            let name: String = property(source, kTISPropertyLocalizedName),
            let data: Data = property(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let language = (property(source, kTISPropertyInputSourceLanguages) as [String]?)?.first ?? "und"
        return LayoutKeyboard(id: id, name: name, language: language, layout: KeyLayout(data: data))
    }

    private static func layout(_ id: String) -> KeyLayout? {
        list(id, includeAllInstalled: true).lazy.compactMap(layoutKeyboard).first?.layout
    }

    /// What each input method does with keys. Apple's are known by name; a third-party method gets
    /// a model when its language says how readings are spelled, and is left out otherwise.
    static func inputMethod(id: String, name: String, language: String) -> (any Keyboard)? {
        guard let latin = asciiCapable()?.layout else { return nil }
        let base = language.split(separator: "-").first.map(String.init) ?? language

        switch id {
        case "com.apple.inputmethod.Korean.2SetKorean":
            guard let jamo = layout("com.apple.keylayout.2SetHangul") else { return nil }
            return ComposedKeyboard(
                id: id, name: name, language: "ko", layout: jamo, composer: HangulComposer())
        case "com.apple.inputmethod.VietnameseIM.VietnameseTelex",
            "com.apple.inputmethod.VietnameseIM.VietnameseSimpleTelex":
            return ComposedKeyboard(
                id: id, name: name, language: "vi", layout: latin, composer: VietnameseComposer(.telex))
        case "com.apple.inputmethod.VietnameseIM.VietnameseVNI":
            return ComposedKeyboard(
                id: id, name: name, language: "vi", layout: latin, composer: VietnameseComposer(.vni))
        case _ where id.hasSuffix(".Roman"):
            // The Latin mode inside a Japanese input method types like the Latin layout.
            return LayoutKeyboard(id: id, name: name, language: "en", layout: latin)
        case _ where id.contains("FullWidthRoman"):
            return nil
        case _ where id.contains("Kotoeri.KanaTyping"):
            return layout("com.apple.keylayout.KANA").map {
                ConvertingKeyboard(id: id, name: name, language: "ja", layout: $0, phonotactics: nil)
            }
        default:
            break
        }

        switch base {
        case "ja":
            return ConvertingKeyboard(
                id: id, name: name, language: language, layout: latin, phonotactics: .romaji)
        case "zh" where id.localizedCaseInsensitiveContains("pinyin") || id.hasSuffix(".ITABC"):
            return ConvertingKeyboard(
                id: id, name: name, language: language, layout: latin, phonotactics: .pinyin)
        default:
            // Shape-based Chinese methods, Indic transliteration, romaja and the rest: the engine can
            // hand them keys when asked, but cannot judge a reading for them.
            return ConvertingKeyboard(
                id: id, name: name, language: language, layout: latin, phonotactics: nil)
        }
    }

    private static func list(_ id: String?, includeAllInstalled: Bool) -> [TISInputSource] {
        var filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any
        ]
        // Layouts an input method is built on, like 2-Set Hangul, are installed but never selectable
        // themselves; looking one up by name must still find it.
        if let id {
            filter[kTISPropertyInputSourceID] = id
        } else {
            filter[kTISPropertyInputSourceIsSelectCapable] = true
        }
        let list = TISCreateInputSourceList(filter as CFDictionary, includeAllInstalled)?.takeRetainedValue()
        return list as? [TISInputSource] ?? []
    }
}

private func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? T
}
