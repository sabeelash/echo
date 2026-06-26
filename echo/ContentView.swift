//
//  ContentView.swift
//  echo
//
//  Created by sabeel ashraf on 26/06/2026.
//

import SwiftUI

struct MenuBarView: View {
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

        Divider()

        Button("Quit echo") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
