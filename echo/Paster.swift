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

        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
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
