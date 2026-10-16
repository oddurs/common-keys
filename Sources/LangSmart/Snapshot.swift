import AppKit
import SwiftUI
import WorldKey

/// `LangSmart --snapshot out.png` renders the menu's cards in light and dark, once with a day of
/// sample use and once as on the first day, for design review without opening the menu.
@MainActor
enum SnapshotCommand {
    static func run(path: String) {
        let busy = sample()
        let empty = DropdownData(
            today: UsageStats.Day(date: ""), week: Array(repeating: UsageStats.Day(date: ""), count: 7),
            keyboards: busy.keyboards, apps: [], learnedWords: 0, mixedUp: nil, hour: 9)

        func menu(_ data: DropdownData, _ scheme: ColorScheme) -> some View {
            VStack(spacing: 0) {
                ForEach(DropdownPanel.allCases, id: \.self) { PanelView(data: data, panel: $0) }
            }
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .environment(\.colorScheme, scheme)
        }
        let renderer = ImageRenderer(
            content: HStack(alignment: .top, spacing: 24) {
                menu(busy, .light)
                menu(busy, .dark)
                menu(empty, .light)
            }
            .padding(24)
            .background(Color(white: 0.5)))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { fatalError("could not render the menu") }
        do {
            try png.write(to: URL(filePath: path))
        } catch {
            fatalError("could not write \(path): \(error)")
        }
    }

    /// A plausible afternoon: English and Icelandic, a few fixes, three apps.
    private static func sample() -> DropdownData {
        var stats = UsageStats()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let words: [(String, String, Int)] = [
            ("com.apple.keylayout.US", "com.apple.mail", 412),
            ("com.apple.keylayout.Icelandic", "com.apple.MobileSMS", 268),
            ("com.apple.keylayout.US", "com.apple.Notes", 131),
            ("com.apple.keylayout.Icelandic", "com.apple.mail", 57),
        ]
        for (keyboard, app, count) in words {
            for _ in 0..<count {
                stats.recordWord(on: keyboard, in: app, at: today.addingTimeInterval(14 * 3600))
            }
        }
        for (hour, fixes) in [9: 2, 10: 4, 11: 1, 13: 3, 14: 5, 15: 2] {
            for _ in 0..<fixes { stats.recordFix(at: today.addingTimeInterval(Double(hour) * 3600)) }
        }
        stats.recordUndo(at: today.addingTimeInterval(14 * 3600))
        for (back, fixes) in [1: 9, 2: 14, 3: 6, 4: 11, 5: 3, 6: 8] {
            let day = calendar.date(byAdding: .day, value: -back, to: today)!.addingTimeInterval(12 * 3600)
            for _ in 0..<fixes { stats.recordFix(at: day) }
        }
        let now = today.addingTimeInterval(15.5 * 3600)
        let day = stats.day(now)
        return DropdownData(
            today: day, week: stats.last(7, endingAt: now),
            keyboards: [
                ("com.apple.keylayout.US", "U.S.", "🇺🇸"), ("com.apple.keylayout.Icelandic", "Icelandic", "🇮🇸"),
            ],
            apps: [
                .init(bundleID: "com.apple.mail", words: 469, flag: "🇺🇸"),
                .init(bundleID: "com.apple.MobileSMS", words: 268, flag: "🇮🇸"),
                .init(bundleID: "com.apple.Notes", words: 131, flag: nil),
            ],
            learnedWords: 23, mixedUp: ("/", "þ", 14), hour: 15)
    }
}
