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
    @State private var dictation = DictationController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image("MenuBarIcon")
        }

        // TEMPORARY stage-1 debug window for the record→transcribe round-trip.
        // Debug builds only — stripped from exported/release builds.
        #if DEBUG
        Window("Debug", id: "debug") {
            DebugView()
        }
        .windowResizability(.contentSize)
        #endif

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
