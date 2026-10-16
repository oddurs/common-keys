import Foundation

/// The layout last used in each app, so coming back to an app picks up where you left off
/// instead of inheriting whatever the previous app was using.
public struct RecentLayouts: Sendable {
    private var entries: [String: (layoutID: String, at: Date)] = [:]

    public init() {}

    /// Records that `layoutID` was in use in `app`: a word typed there, or a switch made there.
    public mutating func note(_ layoutID: String, in app: String, at time: Date) {
        entries[app] = (layoutID, time)
    }

    /// The layout last used in `app`, if that was within `window` seconds of `now`.
    public func layout(in app: String, now: Date, within window: TimeInterval) -> String? {
        guard let entry = entries[app], now.timeIntervalSince(entry.at) <= window else { return nil }
        return entry.layoutID
    }

    public mutating func forget(_ app: String) {
        entries[app] = nil
    }
}

/// Which layout an app gets when it comes to the front, most considered first.
public enum AppLayoutChoice {
    public static func choose(recent: String?, pinned: String?, usual: String?, preferred: String?) -> String?
    {
        // What you were just doing in this app beats any standing rule about it.
        recent ?? pinned ?? usual ?? preferred
    }
}
