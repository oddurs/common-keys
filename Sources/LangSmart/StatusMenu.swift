import AppKit
import SwiftUI
import WorldKey

/// The menu bar item: the current layout's flag, and a real menu under it: StatBar-style cards for
/// the day's stats, then the keyboards and the few things there are to do.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let engine: Engine
    private let openSettings: () -> Void
    private let item: NSStatusItem

    init(engine: Engine, openSettings: @escaping () -> Void) {
        self.engine = engine
        self.openSettings = openSettings
        // New items go to the far left of the menu bar, which on a full bar with a notch means
        // hidden off-screen. Start next to the system icons instead; ⌘-dragging moves it from there.
        let position = "NSStatusItem Preferred Position LangSmart"
        if UserDefaults.standard.object(forKey: position) == nil {
            UserDefaults.standard.set(Self.startPosition, forKey: position)
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "LangSmart"
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        render()
    }

    /// Points from the right edge of the screen: just left of Control Center and the clock.
    private static let startPosition = 300

    /// Redraws the button whenever anything it shows changes.
    private func render() {
        withObservationTracking {
            guard let button = item.button else { return }
            let layout = engine.currentLayout
            button.title = layout?.flag ?? "⌨︎"
            button.font = .systemFont(ofSize: 15)
            // Dimmed, like a disabled menu item, while LangSmart is not fixing anything.
            button.appearsDisabled = !engine.isWorking
            button.toolTip = [layout?.name, engine.pausedIn.map { "Paused in \($0)" }]
                .compactMap { $0 }.joined(separator: " · ")
        } onChange: {
            Task { @MainActor [weak self] in self?.render() }
        }
    }

    /// Card views exist only while the menu is open, so a closed menu costs nothing.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !engine.trusted {
            let allow = action("Allow Accessibility Access…") { [engine] in engine.openAccessibilitySettings()
            }
            allow.subtitle = "Needed to see and fix what you type"
            allow.image = symbol("hand.raised.fill")
            menu.addItem(allow)
            menu.addItem(.separator())
        }

        let data = DropdownData(engine: engine)
        for panel in DropdownPanel.allCases {
            menu.addItem(hosted(PanelView(data: data, panel: panel)))
        }
        menu.addItem(.separator())

        for layout in engine.layouts {
            let item = action("\(layout.flag)  \(layout.name)") { [engine] in engine.select(layout.id) }
            item.state = layout.id == engine.currentLayoutID ? .on : .off
            if layout.id == engine.preferredLayoutID { item.subtitle = "Preferred" }
            menu.addItem(item)
        }
        if engine.layouts.count > 1 {
            let toggle = action("Next Layout") { [engine] in engine.toggleLayout() }
            toggle.image = symbol("arrow.triangle.2.circlepath")
            if let shortcut = engine.prefs.toggleShortcut, let key = shortcut.menuKey {
                toggle.keyEquivalent = key
                toggle.keyEquivalentModifierMask = shortcut.menuModifiers
            }
            menu.addItem(toggle)
        }

        menu.addItem(.separator())
        if let app = engine.frontApp, let bundleID = app.bundleIdentifier,
            bundleID != Bundle.main.bundleIdentifier
        {
            menu.addItem(appItem(app, bundleID))
        }
        let pause = action(engine.prefs.autoCorrect ? "Pause Fixing" : "Resume Fixing") { [engine] in
            engine.prefs.autoCorrect.toggle()
        }
        pause.image = symbol(engine.prefs.autoCorrect ? "pause.circle" : "play.circle")
        if let app = engine.pausedIn { pause.subtitle = "Paused in \(app)" }
        menu.addItem(pause)

        menu.addItem(.separator())
        let settings = action("Settings…", key: ",", perform: openSettings)
        settings.image = symbol("gearshape")
        menu.addItem(settings)
        let quit = action("Quit LangSmart", key: "q") { NSApp.terminate(nil) }
        quit.image = symbol("power")
        menu.addItem(quit)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Drop the hosting views; menuNeedsUpdate rebuilds them on the next open.
        for item in menu.items { item.view = nil }
    }

    private func hosted(_ view: some View) -> NSMenuItem {
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        let item = NSMenuItem()
        item.view = host
        return item
    }

    /// Tahoe gives standard menu items icons; match them. Earlier releases show none.
    private func symbol(_ name: String) -> NSImage? {
        guard #available(macOS 26, *) else { return nil }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    /// "In Mail" with a submenu: follow what was learned, pin a layout, or pause there.
    private func appItem(_ app: NSRunningApplication, _ bundleID: String) -> NSMenuItem {
        let name = app.localizedName ?? bundleID
        let item = NSMenuItem(title: "In \(name)", action: nil, keyEquivalent: "")
        item.image = app.icon.map { icon in
            let small = icon.copy() as? NSImage ?? icon
            small.size = NSSize(width: 16, height: 16)
            return small
        }
        let pinned = engine.prefs.appLayouts[bundleID]
        let paused = engine.prefs.excludedApps.contains(bundleID)
        let usual = engine.memory.usualLayout(app: bundleID).flatMap { engine.layout($0.id) }
        item.subtitle =
            paused
            ? "Paused" : (pinned.flatMap(engine.layout) ?? usual).map { "Usually \($0.flag) \($0.name)" }

        let submenu = NSMenu()
        let automatic = action("Automatic") { [engine] in
            engine.prefs.appLayouts[bundleID] = nil
            engine.prefs.excludedApps.removeAll { $0 == bundleID }
        }
        automatic.state = pinned == nil && !paused ? .on : .off
        automatic.subtitle = usual.map { "Learned: \($0.name)" } ?? "Still learning"
        submenu.addItem(automatic)
        submenu.addItem(.separator())
        for layout in engine.layouts {
            let choice = action("\(layout.flag)  \(layout.name)") { [engine] in
                engine.prefs.appLayouts[bundleID] = layout.id
                engine.prefs.excludedApps.removeAll { $0 == bundleID }
            }
            choice.state = pinned == layout.id && !paused ? .on : .off
            submenu.addItem(choice)
        }
        submenu.addItem(.separator())
        let pause = action("Pause Here") { [engine] in
            if paused {
                engine.prefs.excludedApps.removeAll { $0 == bundleID }
            } else {
                engine.prefs.excludedApps.append(bundleID)
            }
        }
        pause.state = paused ? .on : .off
        submenu.addItem(pause)
        item.submenu = submenu
        return item
    }

    private func action(_ title: String, key: String = "", perform: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: key)
        let target = MenuAction(perform)
        item.target = target
        item.representedObject = target  // The item holds the only reference.
        return item
    }
}

private final class MenuAction: NSObject {
    private let perform: () -> Void

    init(_ perform: @escaping () -> Void) {
        self.perform = perform
    }

    @objc func run() {
        perform()
    }
}
