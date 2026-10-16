import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = Engine(prefs: Preferences())
    private var statusMenu: StatusMenu?
    private lazy var settings = SettingsWindow(engine: engine)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.mainMenu()
        engine.start()
        statusMenu = StatusMenu(engine: engine) { [weak self] in self?.settings.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.flush()
    }

    /// Never shown, since this is a menu bar app, but it gives the settings window ⌘W and ⌘Q.
    private static func mainMenu() -> NSMenu {
        let app = NSMenu()
        app.addItem(
            withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        app.addItem(
            withTitle: "Quit Common Keys", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let root = NSMenu()
        let item = NSMenuItem(title: "Common Keys", action: nil, keyEquivalent: "")
        item.submenu = app
        root.addItem(item)
        return root
    }
}

/// The settings window: one short pane.
@MainActor
final class SettingsWindow {
    private let engine: Engine
    private var window: NSWindow?

    init(engine: Engine) {
        self.engine = engine
    }

    func show() {
        let window = self.window ?? make()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView().environment(engine))
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: host)
        window.title = "Common Keys Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let path = CommandLine.arguments.dropFirst(index + 1).first ?? "snapshot.png"
    MainActor.assumeIsolated { SnapshotCommand.run(path: path) }
    exit(0)
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
