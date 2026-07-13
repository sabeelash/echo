//
//  Paster.swift
//  echo
//
//  Inserts transcribed text into whatever field is focused, using a hybrid:
//
//    1. Accessibility: set kAXSelectedTextAttribute on the focused element,
//       which inserts at the caret (or replaces the selection) WITHOUT touching
//       the user's clipboard. Only attempted when the element reports the
//       attribute as settable.
//    2. Fallback: write to the pasteboard and synthesize ⌘V, then restore the
//       previous pasteboard contents. Works everywhere AX insertion doesn't
//       (Electron, web views, terminals, etc.).
//
//  Both paths require Accessibility permission, which echo requests at launch.
//

import AppKit
import ApplicationServices
import os

@MainActor
enum Paster {
    private static let log = Logger(subsystem: "sabeel.echo", category: "paste")

    /// Returns whether the text observably landed. False means neither path
    /// worked; the transcript is left on the clipboard so ⌘V can recover it.
    @discardableResult
    static func paste(_ text: String) async -> Bool {
        guard !text.isEmpty else { return true }
        if insertViaAX(text) {
            log.info("Pasted via AX")
            return true
        }
        log.info("AX insertion unavailable — using clipboard fallback")
        return await pasteViaClipboard(text)
    }

    // MARK: - Accessibility insertion

    private static func insertViaAX(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return false }
        let element = focused as! AXUIElement

        // Insert at the caret only if this element actually supports it.
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }

        // Browsers (Chrome) and WebKit web views report kAXSelectedTextAttribute
        // as settable and even return .success from the write, but silently
        // ignore it — nothing lands in the field. Snapshot the character count
        // and confirm it grew; if it didn't, report failure so the caller uses
        // the clipboard fallback. (Caret insertion always increases the count;
        // we can't read it back, we can't trust the write either.)
        guard let before = characterCount(of: element) else { return false }

        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success else {
            return false
        }

        guard let after = characterCount(of: element), after > before else { return false }
        return true
    }

    /// Reads kAXNumberOfCharactersAttribute (cheap — just an Int, unlike reading
    /// the full kAXValueAttribute of a large document). Returns nil if the
    /// element doesn't expose it, which we treat as "can't verify".
    private static func characterCount(of element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &value) == .success,
              let number = value as? Int else { return nil }
        return number
    }

    // MARK: - Clipboard fallback

    private static func pasteViaClipboard(_ text: String) async -> Bool {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)

        // Write the transcript through a lazy data provider rather than
        // directly: the provider callback fires exactly when the target app
        // reads the string in response to ⌘V. That's the "paste consumed"
        // signal a fixed sleep only guesses at (and that changeCount can't
        // give — reads don't bump it). Slow apps get the full timeout; fast
        // ones release the clipboard in a few milliseconds.
        let provider = ConsumptionTrackingProvider(text: text)
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        pb.clearContents()
        pb.writeObjects([item])
        let ourChangeCount = pb.changeCount

        sendCommandV()

        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !provider.consumed && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        // Brief grace so an app that reads the string more than once while
        // handling the paste still sees the transcript, not the restore.
        try? await Task.sleep(for: .milliseconds(50))

        // Nothing read the pasteboard within the deadline: the ⌘V never landed
        // (no editable field focused, Accessibility permission revoked, …).
        // Skip the restore so the transcript stays on the clipboard — a manual
        // ⌘V still recovers the dictation.
        guard provider.consumed else {
            log.error("Paste not consumed — leaving transcript on clipboard")
            return false
        }

        // If something else wrote to the pasteboard while we waited (clipboard
        // manager, the user copying), restoring now would clobber it — leave
        // the pasteboard alone.
        guard pb.changeCount == ourChangeCount else {
            log.info("Pasteboard changed while pasting — skipping restore")
            return true
        }
        restore(saved, to: pb)
        return true
    }

    /// Serves the transcript to whoever reads the pasteboard and records that
    /// it happened. The callback can arrive on a non-main thread, so the flag
    /// is lock-protected.
    private final class ConsumptionTrackingProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
        private let text: String
        private let state = OSAllocatedUnfairLock(initialState: false)

        var consumed: Bool { state.withLock { $0 } }

        init(text: String) {
            self.text = text
        }

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            item.setString(text, forType: type)
            state.withLock { $0 = true }
        }
    }

    private static func snapshot(_ pb: NSPasteboard) -> [NSPasteboardItem] {
        (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pb: NSPasteboard) {
        pb.clearContents()
        if !items.isEmpty { pb.writeObjects(items) }
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // kVK_ANSI_V
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
