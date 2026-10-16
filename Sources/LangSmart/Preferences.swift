import CoreGraphics
import Foundation
import Observation

enum ConvertTrigger: String, CaseIterable, Identifiable {
    case off, doubleShift, doubleRightOption, doubleControl

    var id: Self { self }
    var title: String {
        switch self {
        case .off: "Off"
        case .doubleShift: "Double-tap ⇧ Shift"
        case .doubleRightOption: "Double-tap right ⌥ Option"
        case .doubleControl: "Double-tap ⌃ Control"
        }
    }
    var keyCodes: Set<UInt16> {
        switch self {
        case .off: []
        case .doubleShift: [56, 60]
        case .doubleRightOption: [61]
        case .doubleControl: [59, 62]
        }
    }
    var flag: CGEventFlags {
        switch self {
        case .off: []
        case .doubleShift: .maskShift
        case .doubleRightOption: .maskAlternate
        case .doubleControl: .maskControl
        }
    }
}

/// The few things worth choosing. Everything else has one right answer, which the engine uses.
@MainActor @Observable
final class Preferences {
    @ObservationIgnored private let defaults = UserDefaults.standard

    var autoCorrect: Bool { didSet { defaults.set(autoCorrect, forKey: "autoCorrect") } }
    var convertTrigger: ConvertTrigger {
        didSet { defaults.set(convertTrigger.rawValue, forKey: "convertTrigger") }
    }
    var toggleShortcut: Shortcut? { didSet { store(toggleShortcut, "toggleShortcut") } }
    var excludedApps: [String] { didSet { defaults.set(excludedApps, forKey: "excludedApps") } }
    /// Layouts the user pinned to apps, by bundle identifier. Wins over what was learned.
    var appLayouts: [String: String] { didSet { defaults.set(appLayouts, forKey: "appLayouts") } }

    /// Commands and code are not words; fixing them would do harm.
    static let defaultExcludedApps = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
    ]

    init() {
        let d = defaults
        autoCorrect = d.object(forKey: "autoCorrect") as? Bool ?? true
        convertTrigger = d.string(forKey: "convertTrigger").flatMap(ConvertTrigger.init) ?? .doubleRightOption
        toggleShortcut =
            d.object(forKey: "toggleShortcut") == nil
            ? Shortcut.defaultToggle : Self.load(Shortcut?.self, "toggleShortcut", from: d) ?? nil
        excludedApps = d.stringArray(forKey: "excludedApps") ?? Self.defaultExcludedApps
        appLayouts = d.dictionary(forKey: "appLayouts") as? [String: String] ?? [:]
    }

    private func store(_ value: some Encodable, _ key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            preconditionFailure("Shortcut values always encode: \(error)")
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
