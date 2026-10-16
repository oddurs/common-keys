import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import WorldKey

/// The whole of Settings. Common Keys works out the rest by watching how you type.
struct SettingsView: View {
    @Environment(Engine.self) private var engine
    @State private var launchError: String?
    @State private var confirmingReset = false
    private static let paused = "paused"

    var body: some View {
        @Bindable var prefs = engine.prefs
        Form {
            Section {
                Toggle("Launch at login", isOn: launchAtLogin)
            } footer: {
                if let launchError {
                    Text(launchError).foregroundStyle(.red)
                } else {
                    Text(
                        "Common Keys fixes words typed on the wrong keyboard and learns as you go. There is nothing else to set up."
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section("Shortcuts") {
                LabeledContent("Next layout") {
                    ShortcutRecorder(shortcut: prefs.toggleShortcut) { new in
                        prefs.toggleShortcut = new
                        engine.applyShortcuts()
                    }
                }
                Picker("Convert last word", selection: $prefs.convertTrigger) {
                    ForEach(ConvertTrigger.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                ForEach(apps, id: \.self) { bundleID in
                    HStack(spacing: 10) {
                        AppLabel(bundleID: bundleID)
                        Spacer()
                        Picker("Layout", selection: choice(bundleID)) {
                            Text(automaticTitle(bundleID)).tag("")
                            Divider()
                            ForEach(engine.layouts, id: \.id) { Text("\($0.flag)  \($0.name)").tag($0.id) }
                            Divider()
                            Text("Paused").tag(Self.paused)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                Button("Add App…", action: pickApps)
            } header: {
                Text("Exceptions")
            } footer: {
                Text(
                    "Pin an app to one layout, or pause Common Keys in it. Terminals and code editors start paused."
                )
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Button("Forget Everything…", role: .destructive) { confirmingReset = true }
                        .disabled(engine.memory.isEmpty && engine.stats.days.isEmpty)
                } label: {
                    Text("What it has learned")
                    Text(learnedSummary)
                }
            } footer: {
                Text("Kept on this Mac only, in ~/Library/Application Support/LangSmart.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Forget everything Common Keys has learned?", isPresented: $confirmingReset) {
            Button("Forget Everything", role: .destructive) { engine.forgetEverything() }
        } message: {
            Text("Learned words, mixed-up keys, each app's usual layout, and the stats in the menu.")
        }
    }

    private var learnedSummary: String {
        let memory = engine.memory
        let apps = memory.apps.keys.filter { memory.usualLayout(app: $0) != nil }.count
        return [
            count(memory.words.count, "word"), count(memory.confusions.count, "mixed-up key"),
            count(apps, "app"),
        ].joined(separator: " · ")
    }

    private func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    /// Apps with a rule of the user's: pinned or paused. Learned ones need no rule, so they stay out,
    /// and so do apps not installed here: the defaults pause editors this Mac may not have, and a
    /// row of bare bundle identifiers tells nobody anything. Their rule still applies if they arrive.
    private var apps: [String] {
        Set(engine.prefs.appLayouts.keys).union(engine.prefs.excludedApps).filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }.sorted {
            AppLabel.name(of: $0).localizedCaseInsensitiveCompare(AppLabel.name(of: $1)) == .orderedAscending
        }
    }

    private func automaticTitle(_ bundleID: String) -> String {
        guard let usual = engine.memory.usualLayout(app: bundleID), let layout = engine.layout(usual.id)
        else {
            return "Automatic"
        }
        return "Automatic · \(layout.flag)"
    }

    private func choice(_ bundleID: String) -> Binding<String> {
        Binding(
            get: {
                if engine.prefs.excludedApps.contains(bundleID) { return Self.paused }
                return engine.prefs.appLayouts[bundleID] ?? ""
            },
            set: { value in
                engine.prefs.excludedApps.removeAll { $0 == bundleID }
                engine.prefs.appLayouts[bundleID] = nil
                switch value {
                case Self.paused: engine.prefs.excludedApps.append(bundleID)
                case "": break
                default: engine.prefs.appLayouts[bundleID] = value
                }
            })
    }

    private func pickApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(filePath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !apps.contains(id) else { continue }
            // Paused to start with, the usual reason to add an app; the picker changes it.
            engine.prefs.excludedApps.append(id)
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enable in
                do {
                    if enable {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchError = nil
                } catch {
                    launchError = error.localizedDescription
                }
            })
    }
}

private struct AppLabel: View {
    let bundleID: String

    static func name(of bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 20, height: 20)
            Text(Self.name(of: bundleID))
        } else {
            Image(systemName: "app.dashed").frame(width: 20, height: 20).foregroundStyle(.tertiary)
            Text(bundleID).foregroundStyle(.secondary)
        }
    }
}
