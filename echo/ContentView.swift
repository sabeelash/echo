//
//  ContentView.swift
//  echo
//
//  Created by sabeel ashraf on 26/06/2026.
//

import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var settings = AppSettings.shared
    @State private var dictation = DictationController.shared

    var body: some View {
        // Live state + hotkey reminder.
        switch dictation.phase {
        case .idle:         Label("Idle", systemImage: "circle")
        case .recording:    Label("Recording…", systemImage: "record.circle")
        case .transcribing: Label("Transcribing…", systemImage: "ellipsis.circle")
        }

        Text("Hold Fn to dictate")

        Divider()

        Picker("Engine", selection: $settings.engine) {
            ForEach(TranscriptionEngine.allCases) { engine in
                Text(engine.displayName).tag(engine)
            }
        }

        // The Groq model choice only matters on the cloud path.
        if settings.engine == .groq {
            Picker("Model", selection: $settings.model) {
                ForEach(GroqModel.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
        }

        Picker("Style", selection: $settings.style) {
            ForEach(TranscriptionStyle.allCases) { style in
                Text(style.displayName).tag(style)
            }
        }

        MicrophonePicker()

        Divider()

        if !settings.lastTranscript.isEmpty {
            Text("“\(transcriptPreview)”")
        }

        Button("Copy Last Transcript") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(settings.lastTranscript, forType: .string)
        }
        .disabled(settings.lastTranscript.isEmpty)

        Divider()

        if let latency = settings.lastLatency {
            Text(String(format: "Last: %.1fs", latency))
        }
        Text("\(settings.transcriptionsToday) today · \(settings.totalWords) words dictated")

        Divider()

        Menu("Settings") {
            Picker("Language", selection: $settings.languageCode) {
                ForEach(TranscriptionLanguage.all) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }

            Button("Request Permissions") {
                Permissions.logStatusOnLaunch()
                Permissions.requestMicrophone()
                Permissions.checkAccessibility(prompt: true)
            }

            Button("Custom Vocabulary…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "vocabulary")
            }

            Button("Open Debug…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "debug")
            }

            Button("Restart Echo") {
                let url = Bundle.main.bundleURL
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = [url.path]
                task.launch()
                NSApplication.shared.terminate(nil)
            }
        }

        Button("Quit Echo") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    /// First ~40 characters of the last transcript, collapsed to one line, for
    /// an at-a-glance peek before copying.
    private var transcriptPreview: String {
        let oneLine = settings.lastTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return oneLine.count > 40 ? String(oneLine.prefix(40)) + "…" : oneLine
    }
}

/// Mic chooser. Split into its own view so the device list can be (re)read from
/// Core Audio when the menu opens, rather than once at app launch.
private struct MicrophonePicker: View {
    @State private var settings = AppSettings.shared
    @State private var devices: [AudioInputDevice] = []

    var body: some View {
        Picker("Microphone", selection: $settings.inputDeviceUID) {
            Text("System Default").tag(String?.none)
            ForEach(devices) { device in
                Text(device.name).tag(Optional(device.uid))
            }
        }
        .onAppear { devices = AudioDevices.inputDevices() }
    }
}
