//
//  echoApp.swift
//  echo
//
//  Created by sabeel ashraf on 26/06/2026.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Permissions.logStatusOnLaunch()
        Permissions.requestMicrophone()
        Permissions.checkAccessibility(prompt: true)
    }
}

@main
struct echoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("echo", systemImage: "waveform.and.mic") {
            MenuBarView()
        }

        Settings {
            SettingsView()
        }
    }
}
