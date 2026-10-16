import AppKit
import SwiftUI

/// The Common Tools family: Common Stats, Common Keys, and Common Bar. This file is identical in
/// all three apps, so each Settings window ends the same way; change it in all three together.
struct CommonTool: Identifiable {
    let id: String
    let name: String
    let summary: String
    let bundleIdentifier: String

    static let all = [
        CommonTool(
            id: "stats", name: "Common Stats", summary: "System stats in the menu bar",
            bundleIdentifier: "io.github.oddurs.StatBar"),
        CommonTool(
            id: "keys", name: "Common Keys", summary: "Fixes words typed on the wrong keyboard",
            bundleIdentifier: "com.oddurs.langsmart"),
        CommonTool(
            id: "bar", name: "Common Bar", summary: "Hides menu bar icons behind one line",
            bundleIdentifier: "com.oddurs.reasonal"),
    ]

    static let website = URL(string: "https://oddurs.github.io/common-tools/")!

    var page: URL { Self.website.appending(path: "\(id)/") }

    /// Each app ships all three icons, so a tool that isn't installed still shows its own.
    var icon: NSImage? {
        Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "CommonTools")
            .flatMap(NSImage.init(contentsOf:))
    }

    var isThisApp: Bool { Bundle.main.bundleIdentifier == bundleIdentifier }

    var installedURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) }
}

/// The last section of every Common Tools app's Settings: the family, and this app's version.
struct CommonToolsSection: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    private let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""

    var body: some View {
        Section {
            ForEach(CommonTool.all) { CommonToolRow(tool: $0) }
        } header: {
            Text("Common Tools")
        } footer: {
            HStack {
                Text("\(name) \(version)")
                Spacer()
                Link("oddurs.github.io/common-tools", destination: CommonTool.website)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

private struct CommonToolRow: View {
    let tool: CommonTool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = tool.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    RoundedRectangle(cornerRadius: 7).fill(.quaternary)
                }
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(tool.name)
                Text(tool.summary).font(.footnote).foregroundStyle(.secondary)
            }

            Spacer()

            if tool.isThisApp {
                Text("This app").foregroundStyle(.secondary)
            } else if let url = tool.installedURL {
                Button("Open") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
            } else {
                Button("Get…") { NSWorkspace.shared.open(tool.page) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
