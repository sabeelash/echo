//
//  DebugView.swift
//  echo
//
//  TEMPORARY stage-1 harness: a manual button that exercises the full
//  record → save → upload → transcribe round-trip in isolation, before any
//  hotkey wiring exists. Prints the transcript to the console and shows it here.
//  Delete this once the hotkey path (stage 2) is proven.
//

import SwiftUI
import os

@MainActor
@Observable
final class DebugTranscriber {
    enum Phase: Equatable { case idle, recording, transcribing }

    private let log = Logger(subsystem: "sabeel.echo", category: "debug")
    private let recorder = AudioRecorder()
    private let groq = GroqClient()

    var phase: Phase = .idle
    var status: String = "Ready."
    var transcript: String = ""

    func toggle() {
        switch phase {
        case .idle: startRecording()
        case .recording: stopAndTranscribe()
        case .transcribing: break
        }
    }

    private func startRecording() {
        do {
            transcript = ""
            try recorder.start()
            phase = .recording
            status = "Recording… tap Stop when done."
        } catch {
            status = "Failed to start recording: \(error.localizedDescription)"
            log.error("start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopAndTranscribe() {
        guard let url = recorder.stop() else {
            status = "No audio file produced."
            phase = .idle
            return
        }
        phase = .transcribing
        status = "Uploading to Groq…"
        Task {
            do {
                let start = Date()
                let text = try await groq.transcribe(fileURL: url)
                let elapsed = Date().timeIntervalSince(start)
                transcript = text
                status = String(format: "Done in %.2fs", elapsed)
                print("📝 Transcript: \(text)")
                log.info("Transcript: \(text, privacy: .public)")
            } catch {
                transcript = ""
                status = "Error: \(error.localizedDescription)"
                print("❌ Transcription failed: \(error.localizedDescription)")
                log.error("transcribe failed: \(error.localizedDescription, privacy: .public)")
            }
            phase = .idle
        }
    }
}

struct DebugView: View {
    @State private var model = DebugTranscriber()

    var body: some View {
        VStack(spacing: 16) {
            Text("echo — debug round-trip")
                .font(.headline)

            Button(action: model.toggle) {
                Text(buttonTitle).frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.phase == .transcribing)

            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(model.transcript.isEmpty ? "—" : model.transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quinary, in: .rect(cornerRadius: 8))
        }
        .padding()
        .frame(width: 400, height: 300)
    }

    private var buttonTitle: String {
        switch model.phase {
        case .idle: return "Record"
        case .recording: return "Stop & Transcribe"
        case .transcribing: return "Transcribing…"
        }
    }
}
