import AppKit
import SwiftUI

/// A small note under the fixed word, in the spirit of the system's autocorrect bubble:
/// it says what changed and how to take it back, then gets out of the way.
@MainActor
final class FixBubble {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func show(replacement: String, original: String, flag: String, undoHint: String?) {
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            // Give the app a moment to draw the fixed word, so we can find where it is.
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            guard let self, let word = Caret.boundsOfWord(endingBeforeCaret: replacement.count + 1) else {
                return
            }
            self.present(
                BubbleView(replacement: replacement, original: original, flag: flag, undoHint: undoHint),
                under: word)
            do { try await Task.sleep(for: .seconds(2.2)) } catch { return }
            self.fadeOut()
        }
    }

    func hide() {
        dismissal?.cancel()
        fadeOut()
    }

    private func present(_ view: BubbleView, under word: CGRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: view)
        panel.contentView = host
        let size = host.fittingSize
        // Accessibility reports top-left-origin coordinates; AppKit wants bottom-left.
        let top = (NSScreen.screens.first?.frame.maxY ?? 0) - word.maxY
        panel.setFrame(
            NSRect(x: word.minX - 8, y: top - size.height - 3, width: size.width, height: size.height),
            display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    private func fadeOut() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return panel
    }
}

private struct BubbleView: View {
    let replacement: String
    let original: String
    let flag: String
    let undoHint: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(flag)
            Text(replacement).fontWeight(.medium)
            Text(original).strikethrough().foregroundStyle(.secondary)
            if let undoHint {
                Text(undoHint).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .padding(6)
        .fixedSize()
    }
}

/// Where the text cursor is, through the Accessibility API. Many apps answer; some do not,
/// and then there is simply no bubble.
@MainActor
enum Caret {
    static func boundsOfWord(endingBeforeCaret length: Int) -> CGRect? {
        let system = AXUIElementCreateSystemWide()
        // A hung app must not stall the event tap's thread.
        AXUIElementSetMessagingTimeout(system, 0.1)
        guard let focused = attribute(system, kAXFocusedUIElementAttribute, AXUIElementGetTypeID()),
            let selection = attribute(
                focused as! AXUIElement, kAXSelectedTextRangeAttribute, AXValueGetTypeID())
        else { return nil }
        let element = focused as! AXUIElement
        var caret = CFRange()
        guard AXValueGetValue(selection as! AXValue, .cfRange, &caret) else { return nil }
        var word = CFRange(location: max(caret.location - length, 0), length: min(length, caret.location))
        guard word.length > 0, let range = AXValueCreate(.cfRange, &word) else { return nil }
        var value: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else {
            return nil
        }
        return rect
    }

    /// The attribute's value, if it has the expected Core Foundation type.
    private static func attribute(_ element: AXUIElement, _ name: String, _ type: CFTypeID) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value,
            CFGetTypeID(value) == type
        else { return nil }
        return value
    }
}
