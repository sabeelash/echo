//
//  echoApp.swift
//  echo
//
//  Created by sabeel ashraf on 26/06/2026.
//

import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dictation = DictationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Permissions.logStatusOnLaunch()
        Permissions.requestMicrophone()
        Permissions.checkAccessibility(prompt: true)
        dictation.start()
    }
}

@main
struct echoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("echo", systemImage: "waveform.and.mic") {
            MenuBarView()
        }

        // TEMPORARY stage-1 debug window for the record→transcribe round-trip.
        Window("Debug", id: "debug") {
            DebugView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}
