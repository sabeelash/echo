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
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var isDown = false
    /// Set when Esc aborts the current hold, so the eventual Fn release is
    /// swallowed instead of triggering a transcription.
    private var cancelledThisHold = false

    private static let escKeyCode: UInt16 = 53

    /// Called when Fn goes down (start of hold) and up (release).
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    /// Called when Esc is pressed mid-hold — abort without transcribing.
    var onCancel: () -> Void = {}

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

    /// Esc-to-cancel monitors, live only for the duration of a hold. A global
    /// keyDown monitor is delivered every keystroke in every app, so keeping
    /// one installed while idle would wake echo on each systemwide key press
    /// just to hit the `isDown` early-return.
    private func installKeyMonitors() {
        guard globalKeyMonitor == nil else { return }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleKeyDown(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Swallow the Esc that cancelled a hold so it doesn't also act on
            // whichever echo window is key.
            (self?.handleKeyDown(event) == true) ? nil : event
        }
    }

    private func removeKeyMonitors() {
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        globalKeyMonitor = nil
        localKeyMonitor = nil
    }

    func stop() {
        for monitor in [globalMonitor, localMonitor, globalKeyMonitor, localKeyMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        globalMonitor = nil
        localMonitor = nil
        globalKeyMonitor = nil
        localKeyMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        let fnDown = event.modifierFlags.contains(.function)
        if fnDown && !isDown {
            isDown = true
            cancelledThisHold = false
            // Install before onPress so Esc works from the instant recording starts.
            installKeyMonitors()
            onPress()
        } else if !fnDown && isDown {
            isDown = false
            removeKeyMonitors()
            if cancelledThisHold {
                cancelledThisHold = false
            } else {
                onRelease()
            }
        }
    }

    /// Returns true when the event was an Esc that cancelled the current hold.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isDown, !cancelledThisHold, event.keyCode == Self.escKeyCode else { return false }
        cancelledThisHold = true
        log.info("Esc pressed mid-hold — cancelling")
        onCancel()
        return true
    }
}
