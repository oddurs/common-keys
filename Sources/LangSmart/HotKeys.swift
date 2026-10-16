import AppKit
import Carbon
import SwiftUI
import WorldKey

/// A global key combination, stored in Carbon's terms because that is what registers it.
struct Shortcut: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultToggle = Shortcut(keyCode: 49, modifiers: UInt32(optionKey | shiftKey))

    /// A shortcut from a key press, if it is one: a function key, or a key held with ⌘, ⌃ or ⌥.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = 0
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        let functionKey = Self.functionKeys[event.keyCode] != nil
        guard functionKey || modifiers & (cmdKey | optionKey | controlKey) != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: UInt32(modifiers))
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    var flags: CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
        return flags
    }

    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyName
    }

    /// The key equivalent a menu item shows for this shortcut, when the key has one.
    var menuKey: String? {
        if keyCode == 49 { return " " }
        if let name = Self.functionKeys[UInt16(keyCode)], let number = Int(name.dropFirst()) {
            return String(UnicodeScalar(NSF1FunctionKey + number - 1).map(Character.init) ?? " ")
        }
        guard Self.specialKeys[UInt16(keyCode)] == nil else { return nil }
        return keyName.lowercased()
    }

    var menuModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    private var keyName: String {
        let code = UInt16(keyCode)
        if let name = Self.specialKeys[code] ?? Self.functionKeys[code] { return name }
        let text = InputSources.asciiCapable()?.text(for: [KeyStroke(code)]) ?? ""
        return text.isEmpty ? "#\(keyCode)" : text.uppercased()
    }

    private static let specialKeys: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]

    private static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19",
    ]
}

/// System-wide shortcuts through Carbon's hot key API, which needs no special permission.
@MainActor
final class HotKeys {
    private var registered: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]

    init() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(), hotKeyHandler, 1, &spec, Unmanaged.passUnretained(self).toOpaque(),
            nil)
        precondition(
            status == noErr, "Installing the hot key handler cannot fail on a running app: \(status)")
    }

    /// Replaces every registration. Returns the shortcuts another app already owns.
    func register(_ bindings: [(Shortcut, () -> Void)]) -> Set<Shortcut> {
        unregisterAll()
        var taken: Set<Shortcut> = []
        for (index, (shortcut, action)) in bindings.enumerated() {
            let id = EventHotKeyID(signature: 0x4C53_6D74, id: UInt32(index))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered.append(ref)
                actions[UInt32(index)] = action
            } else {
                taken.insert(shortcut)
            }
        }
        return taken
    }

    func unregisterAll() {
        for ref in registered { UnregisterEventHotKey(ref) }
        registered = []
        actions = [:]
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }
}

private func hotKeyHandler(_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?)
    -> OSStatus
{
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr else { return status }
    let hotKeys = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
    // Carbon delivers hot keys on the main thread.
    MainActor.assumeIsolated { hotKeys.fire(id.id) }
    return noErr
}

/// Click, then press the combination. Escape cancels; Delete clears.
struct ShortcutRecorder: View {
    @Environment(Engine.self) private var engine
    let shortcut: Shortcut?
    let onChange: (Shortcut?) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: start) {
                Text(recording ? "Type shortcut…" : shortcut?.display ?? "Record Shortcut")
                    .foregroundStyle(shortcut == nil || recording ? .secondary : .primary)
                    .frame(minWidth: 110)
            }
            if let shortcut, engine.takenShortcuts.contains(shortcut) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("Another app already uses this shortcut")
            }
            if shortcut != nil, !recording {
                Button {
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        guard !recording else { return }
        recording = true
        // Registered shortcuts would swallow the very keys being recorded.
        engine.suspendShortcuts()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                switch event.keyCode {
                case 53: stop()
                case 51 where event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty:
                    onChange(nil)
                    stop()
                default:
                    if let shortcut = Shortcut(event: event) {
                        onChange(shortcut)
                        stop()
                    } else {
                        NSSound.beep()
                    }
                }
            }
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        engine.applyShortcuts()
    }
}
