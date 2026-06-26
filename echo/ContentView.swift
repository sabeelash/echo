//
//  ContentView.swift
//  echo
//
//  Created by sabeel ashraf on 26/06/2026.
//

import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // SettingsLink is the modern (macOS 14+) way to open the Settings
        // scene. It opens and front-most-activates the window for us, so an
        // accessory app doesn't need to be .regular to show preferences.
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Request Permissions") {
            Permissions.logStatusOnLaunch()
            Permissions.requestMicrophone()
            Permissions.checkAccessibility(prompt: true)
        }

        Button("Open Debug…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "debug")
        }

        Divider()

        Button("Restart echo") {
            let url = Bundle.main.bundleURL
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = [url.path]
            task.launch()
            NSApplication.shared.terminate(nil)
        }

        Button("Quit echo") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
