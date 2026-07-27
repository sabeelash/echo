//
//  ContentView.swift
//  echo
//
//  Created by sabeel ashraf on 26/06/2026.
//

import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var settings = AppSettings.shared

    var body: some View {
        // The active configuration at a glance, without opening Settings.
        Text(configSummary)

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

        Text(statsSummary)
            // The menu is rebuilt each time it opens, so this fires per open —
            // roll the daily count over so it never shows yesterday's number.
            .onAppear { settings.rollOverDailyCountIfNeeded() }

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

            LaunchAtLoginToggle()

            Button("Groq API Key…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "api-key")
            }

            Button("Custom Vocabulary…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "vocabulary")
            }

            #if DEBUG
            Button("Open Debug…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "debug")
            }
            #endif
        }

        Button("Help…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "help")
        }

        Button("Quit Echo") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    /// One-line summary of the active configuration, e.g.
    /// "Groq · Turbo · Normal" or "On-device · Lower Case".
    private var configSummary: String {
        var parts: [String]
        switch settings.engine {
        case .groq:
            parts = ["Groq", settings.model == .turbo ? "Turbo" : "Large v3"]
        case .local:
            parts = ["On-device"]
        }
        parts.append(settings.style.displayName)
        return parts.joined(separator: " · ")
    }

    /// Usage stats on one compact line, e.g. "3 today · 1204 words · 1.2s".
    /// The latency segment appears once the first dictation of the session lands.
    private var statsSummary: String {
        var line = "\(settings.transcriptionsToday) today · \(settings.totalWords) words"
        if let latency = settings.lastLatency {
            line += String(format: " · %.1fs", latency)
        }
        return line
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

/// Launch-at-login toggle backed by `SMAppService.mainApp`. The registration
/// status isn't observable, so it's re-read each time the menu opens (the view
/// is recreated per open) and after every toggle in case the call fails.
private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at Login", isOn: $enabled)
            .onChange(of: enabled) { _, wantEnabled in
                guard wantEnabled != (SMAppService.mainApp.status == .enabled) else { return }
                do {
                    if wantEnabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
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
