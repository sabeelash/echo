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

    static func paste(_ text: String) async {
        guard !text.isEmpty else { return }
        if insertViaAX(text) {
            log.info("Pasted via AX")
            return
        }
        log.info("AX insertion unavailable — using clipboard fallback")
        await pasteViaClipboard(text)
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

    private static func pasteViaClipboard(_ text: String) async {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)

        pb.clearContents()
        pb.setString(text, forType: .string)
        sendCommandV()

        // Restore only after the frontmost app has had a chance to read the
        // pasteboard in response to ⌘V.
        try? await Task.sleep(for: .milliseconds(150))
        restore(saved, to: pb)
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
