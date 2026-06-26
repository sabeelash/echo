//
//  FnHotkeyMonitor.swift
//  echo
//
//  Detects hold/release of the Fn (Globe) key system-wide. Fn is not a
//  registerable hotkey (Carbon/KeyboardShortcuts can't bind it), so we watch
//  the .function modifier flag on .flagsChanged events instead. Arrow/F-keys
//  carry the .function flag too, but they emit .keyDown — not .flagsChanged —
//  so watching flag changes isolates the physical Fn key.
//
//  Requires Accessibility permission (already requested at launch) for the
//  global monitor to receive events from other apps.
//

import AppKit
import os

@MainActor
final class FnHotkeyMonitor {
    private let log = Logger(subsystem: "sabeel.echo", category: "hotkey")
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isDown = false

    /// Called when Fn goes down (start of hold) and up (release).
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        // Local monitor covers the case where one of echo's own windows is key.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
        log.info("Fn monitor started")
    }

    func stop() {
        if let g = globalMonitor { NSEvent.removeMonitor(g) }
        if let l = localMonitor { NSEvent.removeMonitor(l) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        let fnDown = event.modifierFlags.contains(.function)
        if fnDown && !isDown {
            isDown = true
            onPress()
        } else if !fnDown && isDown {
            isDown = false
            onRelease()
        }
    }
}
