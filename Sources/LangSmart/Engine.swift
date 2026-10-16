import AppKit
import Carbon
import Observation
import WorldKey
import os

private let log = Logger(subsystem: "com.oddurs.langsmart", category: "engine")

/// Watches typing, fixes words typed in the wrong layout, and learns from the user's own fixes
/// and from which language they write in each app.
/// Everything runs on the main thread: the event tap is attached to the main run loop.
@MainActor @Observable
final class Engine {
    let prefs: Preferences
    private(set) var layouts: [any Keyboard] = []
    private(set) var currentLayoutID: String?
    private(set) var trusted = AXIsProcessTrusted()
    private(set) var frontApp = NSWorkspace.shared.frontmostApplication
    private(set) var memory: Memory
    private(set) var stats: UsageStats
    private(set) var takenShortcuts: Set<Shortcut> = []

    @ObservationIgnored private var tracker = WordTracker(layoutID: "")
    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private let lexicon = SystemLexicon()
    @ObservationIgnored private let injector = Injector()
    @ObservationIgnored private let hotKeys = HotKeys()
    @ObservationIgnored private let bubble = FixBubble()
    @ObservationIgnored private var lastFix: Fix?
    @ObservationIgnored private var doubleTap = DoubleTap()

    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var awaitingTrust = false
    @ObservationIgnored private var recent = RecentLayouts()
    /// The layout we last switched to ourselves, so the change notification is not taken for the user's.
    @ObservationIgnored private var expectedLayoutID: String?

    /// A conversion we made, kept until the next key so it can be undone.
    private struct Fix {
        var strokes: [KeyStroke]
        var boundary: KeyStroke?
        var from: any Keyboard
        var to: any Keyboard
        var automatic: Bool
        var original: String { from.text(for: strokes) }
        var replacement: String { to.text(for: strokes) }
    }

    init(prefs: Preferences) {
        self.prefs = prefs
        memory = Self.load(Memory.self, from: Self.memoryURL) ?? Memory()
        stats = Self.load(UsageStats.self, from: Self.statsURL) ?? UsageStats()
    }

    // MARK: Lifecycle

    func start() {
        reloadLayouts()
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            forName: .init(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutDidChange() }
        }
        distributed.addObserver(
            forName: .init(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadLayouts() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            MainActor.assumeIsolated {
                self?.appDidActivate(pid.flatMap(NSRunningApplication.init(processIdentifier:)))
            }
        }
        if trusted { installTap() } else { requestAccess() }
    }

    /// Writes pending memory now, for quitting.
    func flush() {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        save()
    }

    /// Shows the system prompt, then waits for the user to flip the switch in System Settings.
    func requestAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        awaitTrust()
    }

    func openAccessibilitySettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
        awaitTrust()
    }

    private func awaitTrust() {
        guard !awaitingTrust else { return }
        awaitingTrust = true
        Task { [weak self] in
            while let self, !self.trusted {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                self.trusted = AXIsProcessTrusted()
            }
            self?.awaitingTrust = false
            self?.installTap()
        }
    }

    private func installTap() {
        guard tap == nil else { return }
        let types: [CGEventType] = [
            .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask, callback: tapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            log.error("Could not create the event tap even though Accessibility access is granted")
            trusted = false
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
    }

    // MARK: Shortcuts

    func applyShortcuts() {
        var bindings: [(Shortcut, () -> Void)] = []
        if let toggle = prefs.toggleShortcut {
            bindings.append((toggle, { [weak self] in self?.toggleLayout() }))
        }

        takenShortcuts = hotKeys.register(bindings)
    }

    func suspendShortcuts() {
        hotKeys.unregisterAll()
    }

    private var registeredShortcuts: [Shortcut] {
        [prefs.toggleShortcut].compactMap { $0 }
    }

    // MARK: State for the UI

    var currentLayout: (any Keyboard)? { layouts.first { $0.id == currentLayoutID } }
    /// The first layout in the system's input menu: the one the user set up first and returns to.
    var preferredLayoutID: String? { layouts.first?.id }
    var candidates: [any Keyboard] { layouts }

    /// The frontmost app's name when LangSmart is paused for it.
    var pausedIn: String? {
        guard let app = frontApp, let id = app.bundleIdentifier, prefs.excludedApps.contains(id) else {
            return nil
        }
        return app.localizedName ?? id
    }

    var isWorking: Bool { trusted && prefs.autoCorrect && pausedIn == nil && currentLayout != nil }

    func layout(_ id: String) -> (any Keyboard)? {
        layouts.first { $0.id == id } ?? InputSources.keyboard(id)
    }

    /// The layout `bundleID` should have: what was last used there, what the user pinned, what they
    /// usually write there, and failing those the preferred layout when `orPreferred`.
    func layoutForApp(_ bundleID: String?, includeRecent: Bool, orPreferred: Bool) -> String? {
        let available = Set(layouts.map(\.id))
        let usable = { (id: String?) in id.flatMap { available.contains($0) ? $0 : nil } }
        let recentID = bundleID.flatMap { app in
            recent.layout(in: app, now: .now, within: Self.recentWindow)
        }
        return AppLayoutChoice.choose(
            recent: includeRecent ? usable(recentID) : nil,
            pinned: usable(bundleID.flatMap { prefs.appLayouts[$0] }),
            usual: usable(bundleID.flatMap { memory.usualLayout(app: $0)?.id }),
            preferred: orPreferred ? usable(preferredLayoutID) : nil)
    }

    /// A switch the user asked for, from the menu, a shortcut or a conversion.
    func select(_ id: String) {
        activate(id)
        noteRecent(id)
    }

    /// A switch LangSmart makes on its own.
    private func activate(_ id: String) {
        guard id != currentLayoutID else { return }
        expectedLayoutID = id
        if InputSources.select(id) {
            currentLayoutID = id
            tracker.setLayout(id)
        } else {
            expectedLayoutID = nil
            log.error("Could not select input source \(id, privacy: .public)")
        }
    }

    private func noteRecent(_ layoutID: String?) {
        guard let layoutID, let app = frontApp?.bundleIdentifier else { return }
        recent.note(layoutID, in: app, at: .now)
    }

    func toggleLayout() {
        let ring = candidates.count > 1 ? candidates : layouts
        guard !ring.isEmpty else { return }
        let index = ring.firstIndex { $0.id == currentLayoutID } ?? -1
        select(ring[(index + 1) % ring.count].id)
    }

    func forget(_ signature: String) {
        memory.forget(signature)
        saveSoon()
    }

    func forgetApp(_ bundleID: String) {
        memory.forgetApp(bundleID)
        recent.forget(bundleID)
        saveSoon()
    }

    func forgetEverything() {
        memory = Memory()
        stats = UsageStats()
        saveSoon()
    }

    // MARK: Events

    /// Returns whether the event should continue to the app.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent, _ proxy: CGEventTapProxy) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        case _ where event.getIntegerValueField(.eventSourceUserData) == Injector.marker:
            return true
        case .keyDown:
            return keyDown(event, proxy)
        case .flagsChanged:
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let now = ProcessInfo.processInfo.systemUptime
            if doubleTap.update(keyCode: keyCode, flags: event.flags, trigger: prefs.convertTrigger, now: now)
            {
                convertLastWord(proxy)
            }
            return true
        default:
            // A click can move the cursor anywhere.
            tracker.reset()
            lastFix = nil
            doubleTap.reset()
            bubble.hide()
            return true
        }
    }

    private func keyDown(_ event: CGEvent, _ proxy: CGEventTapProxy) -> Bool {
        doubleTap.reset()
        let fix = lastFix
        lastFix = nil

        let flags = event.flags
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if let fix, modifiers == .maskCommand, isZ(keyCode) {
            undo(fix, proxy)
            return false
        }
        if fix != nil { bubble.hide() }

        let isShortcut = registeredShortcuts.contains { $0.keyCode == keyCode && $0.flags == modifiers }
        // What a converting input method shows is the user's pick, so there is no word to follow.
        guard !isShortcut, pausedIn == nil, !IsSecureEventInputEnabled(), let keyboard = currentLayout,
            keyboard.kind != .converting, !flags.contains(.maskCommand), !flags.contains(.maskControl)
        else {
            tracker.reset()
            return true
        }
        let stroke = KeyStroke(
            keyCode, shift: flags.contains(.maskShift), option: flags.contains(.maskAlternate),
            capsLock: flags.contains(.maskAlphaShift))
        switch KeyKind(keyCode: keyCode) {
        case .character:
            tracker.type(stroke)
        case .backspace where keyboard.kind == .composing:
            // A composing method takes syllables apart one key at a time, then deletes whole ones;
            // following that exactly is not worth the risk of fixing the wrong text.
            tracker.reset()
        case .backspace:
            tracker.backspace(wholeWord: flags.contains(.maskAlternate), now: .now)
        case .boundary:
            return endWord(with: stroke, proxy)
        case .other:
            tracker.reset()
        }
        return true
    }

    private func isZ(_ keyCode: UInt16) -> Bool {
        currentLayout?.text(for: [KeyStroke(keyCode)]).lowercased() == "z"
    }

    private func endWord(with boundary: KeyStroke, _ proxy: CGEventTapProxy) -> Bool {
        let word = tracker.currentWord
        if let retype = tracker.end(with: boundary, now: .now) { learn(retype) }
        guard let word, let from = layout(word.layoutID) else { return true }

        let detector = Detector()
        let decision =
            prefs.autoCorrect
            ? detector.decide(
                word.strokes, typedIn: from, candidates: candidates, memory: memory, lexicon: lexicon)
            : nil
        noteLanguage(
            decision?.targetID
                ?? detector.clearestReading(word.strokes, candidates: candidates, lexicon: lexicon))
        let app = frontApp?.bundleIdentifier
        guard let decision, let to = layout(decision.targetID) else {
            stats.recordWord(on: from.id, in: app, at: .now)
            noteRecent(currentLayoutID)
            return true
        }

        // The boundary is held back and replayed after the fix, so it lands after the fixed word.
        // It has not reached a composing method either, so its last syllable is still open.
        swap(
            word.strokes, from: from, to: to, erasing: from.erasures(for: word.strokes, committed: false),
            then: boundary, switchLayout: true, proxy)
        tracker.relabelPrevious(to.id)
        noteRecent(to.id)
        stats.recordWord(on: to.id, in: app, at: .now)
        stats.recordFix(at: .now)
        remember(Fix(strokes: word.strokes, boundary: boundary, from: from, to: to, automatic: true))
        return false
    }

    /// The shortcut: undo the fix we just made, or convert the word before the cursor.
    private func convertLastWord(_ proxy: CGEventTapProxy) {
        guard trusted, pausedIn == nil, !IsSecureEventInputEnabled() else { return }
        if let fix = lastFix { return undo(fix, proxy) }

        let word: TrackedWord
        let boundary: KeyStroke?
        if let current = tracker.currentWord {
            (word, boundary) = (current, nil)
        } else if let previous = tracker.previous, previous.boundary.keyCode == 49 {
            // Only across a space: deleting a return or tab may already have sent or moved something.
            (word, boundary) = (previous.word, previous.boundary)
        } else {
            return NSSound.beep()
        }

        let detector = Detector(minLength: 1)
        guard let from = layout(word.layoutID), from.kind != .converting,
            let best = detector.alternatives(
                word.strokes, typedIn: from, candidates: candidates, memory: memory, lexicon: lexicon
            ).first,
            let to = layout(best.targetID)
        else { return NSSound.beep() }

        let erasing = from.erasures(for: word.strokes, committed: boundary != nil) + (boundary == nil ? 0 : 1)
        swap(word.strokes, from: from, to: to, erasing: erasing, then: boundary, switchLayout: true, proxy)
        if boundary == nil { tracker.relabelCurrent(to.id) } else { tracker.relabelPrevious(to.id) }
        noteRecent(to.id)
        memory.learn(word.strokes, from: from, to: to)
        saveSoon()
        remember(Fix(strokes: word.strokes, boundary: boundary, from: from, to: to, automatic: false))
    }

    private func undo(_ fix: Fix, _ proxy: CGEventTapProxy) {
        lastFix = nil
        bubble.hide()
        guard fix.boundary.map({ $0.keyCode == 49 }) ?? true else { return NSSound.beep() }
        let erasing =
            fix.to.erasures(for: fix.strokes, committed: fix.boundary != nil) + (fix.boundary == nil ? 0 : 1)
        swap(
            fix.strokes, from: fix.to, to: fix.from, erasing: erasing, then: fix.boundary, switchLayout: true,
            proxy)
        if fix.boundary == nil {
            tracker.relabelCurrent(fix.from.id)
        } else {
            tracker.relabelPrevious(fix.from.id)
        }
        noteRecent(fix.from.id)
        if fix.automatic {
            memory.keep(fix.strokes, in: fix.from.id)
            stats.recordUndo(at: .now)
        } else {
            memory.unlearn(fix.strokes)
        }
        noteLanguage(fix.from.id)
        saveSoon()
    }

    /// Replaces what `strokes` typed on `from` with what they mean on `to`.
    ///
    /// Between ordinary layouts the text goes out at once, right behind the key being handled. An
    /// input method in the way would read typed Unicode as key presses, so then the old text is
    /// erased, the layout switched, and the new text typed a moment later. A converting method is
    /// handed the keys themselves, and composes the reading for the user to convert.
    private func swap(
        _ strokes: [KeyStroke], from: any Keyboard, to: any Keyboard, erasing: Int, then boundary: KeyStroke?,
        switchLayout: Bool, _ proxy: CGEventTapProxy
    ) {
        if from.kind == .direct && to.kind == .direct {
            injector.replace(deleting: erasing, with: to.text(for: strokes), then: boundary, via: proxy)
            if switchLayout { activate(to.id) }
            return
        }
        if from.kind == .direct && to.kind == .composing {
            injector.replace(deleting: erasing, with: to.text(for: strokes), then: boundary, via: proxy)
            afterInputSettles { [weak self] in self?.activate(to.id) }
            return
        }
        injector.replace(deleting: erasing, with: "", then: nil, via: proxy)
        activate(to.id)
        let injector = self.injector
        afterInputSettles {
            if to.kind == .converting {
                // The boundary stays out: in these methods space converts, and that is the user's call.
                injector.replay(strokes)
            } else {
                injector.type(to.text(for: strokes), then: boundary)
            }
        }
    }

    /// Records a fix so ⌘Z or the shortcut can take it back, and shows it. A converting method
    /// owns its text from then on, so those fixes are neither shown nor undone.
    private func remember(_ fix: Fix) {
        guard fix.to.kind != .converting else { return }
        lastFix = fix
        announce(fix)
    }

    private func afterInputSettles(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
            work()
        }
    }

    private func announce(_ fix: Fix) {
        bubble.show(replacement: fix.replacement, original: fix.original, flag: fix.to.flag, undoHint: "⌘Z")
    }

    private func learn(_ retype: Retype) {
        guard let from = layout(retype.from), let to = layout(retype.to),
            from.text(for: retype.strokes) != to.text(for: retype.strokes)
        else { return }
        memory.learn(retype.strokes, from: from, to: to)
        saveSoon()
    }

    /// Counts a word toward the language the front app is written in.
    private func noteLanguage(_ layoutID: String?) {
        guard let layoutID, let app = frontApp?.bundleIdentifier else { return }
        memory.recordUse(app: app, layoutID: layoutID)
        saveSoon()
    }

    // MARK: Layout changes

    private func reloadLayouts() {
        layouts = InputSources.enabled()
        currentLayoutID = InputSources.currentID()
        tracker.setLayout(currentLayoutID ?? "")
        applyShortcuts()
    }

    private func layoutDidChange() {
        let id = InputSources.currentID()
        // A change we did not make is the user switching, with the menu or the system shortcut.
        if id != expectedLayoutID { noteRecent(id) }
        expectedLayoutID = nil
        currentLayoutID = id
        tracker.setLayout(id ?? "")
    }

    private func appDidActivate(_ app: NSRunningApplication?) {
        frontApp = app
        tracker.reset()
        lastFix = nil
        bubble.hide()
        // Whatever the previous app was switched to says nothing about this one.
        let choice = layoutForApp(
            app?.bundleIdentifier, includeRecent: true, orPreferred: true)
        if let choice { activate(choice) }
    }

    // MARK: Persistence

    private static let folder = URL.applicationSupportDirectory.appending(path: "LangSmart")
    private static let memoryURL = folder.appending(path: "memory.json")
    private static let statsURL = folder.appending(path: "stats.json")
    /// How long an app remembers the layout last used in it.
    private static let recentWindow: TimeInterval = 60 * 60

    /// A saved file, or nil when there is none yet or it cannot be read.
    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            log.error("Could not read \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            return nil
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // Keep the unreadable file for inspection rather than overwriting it on the next save.
            let aside = url.deletingPathExtension().appendingPathExtension("unreadable.json")
            log.error(
                "\(url.lastPathComponent, privacy: .public) is unreadable, moved aside: \(error, privacy: .public)"
            )
            try? FileManager.default.removeItem(at: aside)
            do { try FileManager.default.moveItem(at: url, to: aside) } catch {
                log.error(
                    "Could not move \(url.lastPathComponent, privacy: .public) aside: \(error, privacy: .public)"
                )
            }
            return nil
        }
    }

    /// Every word updates memory; writing once typing pauses keeps the disk out of the way.
    private func saveSoon() {
        guard pendingSave == nil else { return }
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.save()
        }
    }

    private func save() {
        pendingSave = nil
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try encoder.encode(memory).write(to: Self.memoryURL, options: .atomic)
            try encoder.encode(stats).write(to: Self.statsURL, options: .atomic)
        } catch {
            log.error("Could not save: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private func tapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<Engine>.fromOpaque(refcon).takeUnretainedValue()
    // The tap's run loop source is on the main run loop, so the event never leaves this thread.
    nonisolated(unsafe) let event = event
    nonisolated(unsafe) let proxy = proxy
    let pass = MainActor.assumeIsolated { engine.handle(type, event, proxy) }
    return pass ? Unmanaged.passUnretained(event) : nil
}

/// Detects two quick taps of a modifier with nothing else pressed in between.
private struct DoubleTap {
    private var downAt: TimeInterval?
    private var lastTap: TimeInterval?

    mutating func reset() {
        downAt = nil
        lastTap = nil
    }

    mutating func update(keyCode: UInt16, flags: CGEventFlags, trigger: ConvertTrigger, now: TimeInterval)
        -> Bool
    {
        let modifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        guard trigger.keyCodes.contains(keyCode),
            flags.intersection(modifiers).subtracting(trigger.flag).isEmpty
        else {
            reset()
            return false
        }
        if flags.contains(trigger.flag) {
            downAt = now
            return false
        }
        defer { downAt = nil }
        guard let downAt, now - downAt < 0.3 else {
            lastTap = nil
            return false
        }
        if let lastTap, now - lastTap < 0.45 {
            self.lastTap = nil
            return true
        }
        lastTap = now
        return false
    }
}

/// Types on the user's behalf. Events go out through the tap, right behind the key that
/// triggered them, so nothing typed afterwards can slip in between.
@MainActor
private struct Injector {
    static let marker: Int64 = 0x4C61_6E67
    private let source = CGEventSource(stateID: .privateState)

    func replace(
        deleting count: Int, with text: String, then boundary: KeyStroke?, via proxy: CGEventTapProxy
    ) {
        for _ in 0..<count { press(51, via: proxy) }
        // Typed as Unicode rather than key codes, so it comes out right whichever layout is active.
        for character in text {
            let units = Array(String(character).utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else {
                    continue
                }
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                post(event, flags: [], via: proxy)
            }
        }
        if let boundary { press(boundary.keyCode, flags: boundary.shift ? .maskShift : [], via: proxy) }
    }

    /// Types `text` from outside the tap, for work done after the triggering key is long gone.
    func type(_ text: String, then boundary: KeyStroke?) {
        for character in text {
            for event in unicodeEvents(character) { post(event, flags: [], via: nil) }
        }
        if let boundary {
            for event in keyEvents(boundary.keyCode) {
                post(event, flags: boundary.shift ? .maskShift : [], via: nil)
            }
        }
    }

    /// Presses the keys themselves, so an input method composes them as if typed.
    func replay(_ strokes: [KeyStroke]) {
        for stroke in strokes {
            var flags: CGEventFlags = []
            if stroke.shift { flags.insert(.maskShift) }
            if stroke.option { flags.insert(.maskAlternate) }
            for event in keyEvents(stroke.keyCode) { post(event, flags: flags, via: nil) }
        }
    }

    private func unicodeEvents(_ character: Character) -> [CGEvent] {
        let units = Array(String(character).utf16)
        return [true, false].compactMap { down in
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            return event
        }
    }

    private func keyEvents(_ keyCode: CGKeyCode) -> [CGEvent] {
        [true, false].compactMap { CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: $0) }
    }

    private func press(_ keyCode: CGKeyCode, flags: CGEventFlags = [], via proxy: CGEventTapProxy) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else {
                continue
            }
            post(event, flags: flags, via: proxy)
        }
    }

    private func post(_ event: CGEvent, flags: CGEventFlags, via proxy: CGEventTapProxy?) {
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        if let proxy { event.tapPostEvent(proxy) } else { event.post(tap: .cgSessionEventTap) }
    }
}
