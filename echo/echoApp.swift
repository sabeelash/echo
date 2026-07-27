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
    let dictation = DictationController.shared

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
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image("MenuBarIcon")
        }

        Window("Groq API Key", id: "api-key") {
            APIKeyView()
        }
        .windowResizability(.contentSize)

        Window("Custom Vocabulary", id: "vocabulary") {
            VocabularyView()
        }
        .windowResizability(.contentSize)

        Window("Echo Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }
}
