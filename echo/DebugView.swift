//
//  DebugView.swift
//  echo
//
//  TEMPORARY harness, now doing double duty: the original record → Groq
//  round-trip, plus a head-to-head against the on-device SpeechAnalyzer /
//  SpeechTranscriber prototype (LocalTranscriber). One recording feeds both:
//  the file uploads to Groq at stop (production path) while the same tap
//  buffers stream into the local analyzer *during* recording. Both latencies
//  are measured from the same stop instant.
//

import SwiftUI
import os

@MainActor
@Observable
final class DebugTranscriber {
    enum Phase: Equatable { case idle, preparing, recording, transcribing }

    private let log = Logger(subsystem: "sabeel.echo", category: "debug")
    private let recorder = AudioRecorder()
    private let groq = GroqClient()
    private let local = LocalTranscriber()

    var phase: Phase = .idle
    var status: String = "Ready."
    var groqTranscript = ""
    var groqTime = ""
    var localTranscript = ""
    var localTime = ""

    /// False when the local session failed to start — Groq still runs alone.
    private var localActive = false
    /// Engines still in flight after stop; phase returns to idle at zero.
    private var pending = 0

    func toggle() {
        switch phase {
        case .idle: startRecording()
        case .recording: stopAndTranscribe()
        case .preparing, .transcribing: break
        }
    }

    private func startRecording() {
        phase = .preparing
        status = "Preparing local model…"
        groqTranscript = ""; groqTime = ""
        localTranscript = ""; localTime = ""

        Task {
            // Bring the local session up before the tap starts so model load
            // stays off the measured stop → transcript path. First ever run
            // also downloads the model asset here.
            do {
                local.onPartial = { [weak self] text in
                    guard let self else { return }
                    Task { @MainActor in self.localTranscript = text }
                }
                try await local.startSession(
                    languageCode: AppSettings.shared.languageCode,
                    vocabulary: AppSettings.shared.vocabularyTerms
                )
                localActive = true
            } catch {
                localActive = false
                localTranscript = "Unavailable: \(error.localizedDescription)"
                localTime = "—"
                log.error("local session failed: \(error.localizedDescription, privacy: .public)")
            }

            do {
                recorder.onBuffer = localActive ? { [local] in local.feed($0) } : nil
                try recorder.start(inputDeviceUID: AppSettings.shared.inputDeviceUID)
                phase = .recording
                status = "Recording… tap Stop when done."
            } catch {
                if localActive { local.cancel() }
                status = "Failed to start recording: \(error.localizedDescription)"
                phase = .idle
                log.error("start failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func stopAndTranscribe() {
        let stopped = Date()
        let url = recorder.stop()
        recorder.onBuffer = nil
        guard let url else {
            if localActive { local.cancel() }
            status = "No audio file produced."
            phase = .idle
            return
        }
        phase = .transcribing
        status = "Transcribing…"
        let settings = AppSettings.shared
        pending = localActive ? 2 : 1

        if localActive {
            // The audio already streamed in while recording — this measures
            // only how long finalization takes.
            Task {
                do {
                    let raw = try await local.finish()
                    localTranscript = settings.style.postProcess(raw)
                    localTime = String(format: "%.2fs", Date().timeIntervalSince(stopped))
                } catch {
                    localTranscript = "Error: \(error.localizedDescription)"
                    localTime = "—"
                    log.error("local finish failed: \(error.localizedDescription, privacy: .public)")
                }
                settle()
            }
        }

        Task {
            defer { try? FileManager.default.removeItem(at: url) }
            guard let key = settings.resolvedAPIKey else {
                groqTranscript = "No Groq API key — add one in Settings."
                groqTime = "—"
                settle()
                return
            }
            do {
                let raw = try await groq.transcribe(
                    fileURL: url,
                    key: key,
                    model: settings.model.rawValue,
                    language: settings.languageCode,
                    prompt: settings.groqPrompt
                )
                let text = settings.style.postProcess(raw)
                groqTranscript = text
                groqTime = String(format: "%.2fs", Date().timeIntervalSince(stopped))
                AppSettings.shared.lastTranscript = text
            } catch {
                groqTranscript = "Error: \(error.localizedDescription)"
                groqTime = "—"
                log.error("groq transcribe failed: \(error.localizedDescription, privacy: .public)")
            }
            settle()
        }
    }

    private func settle() {
        pending -= 1
        guard pending <= 0 else { return }
        phase = .idle
        let g = groqTime.isEmpty ? "—" : groqTime
        let l = localTime.isEmpty ? "—" : localTime
        status = "Done — Groq \(g) · Local \(l)"
    }
}

struct DebugView: View {
    @State private var model = DebugTranscriber()

    var body: some View {
        VStack(spacing: 12) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)

            Button(action: model.toggle) {
                Text(buttonTitle).frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0x0C / 255, green: 0x1A / 255, blue: 0x2A / 255))
            .keyboardShortcut(.defaultAction)
            .disabled(model.phase == .preparing || model.phase == .transcribing)

            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)

            resultPane(
                title: "Groq · \(AppSettings.shared.model.rawValue)",
                time: model.groqTime,
                text: model.groqTranscript,
                placeholder: "Groq transcript will show up here."
            )
            resultPane(
                title: "Local · on-device",
                time: model.localTime,
                text: model.localTranscript,
                placeholder: "Local transcript will show up here — live, while you speak."
            )
        }
        .padding()
        .frame(width: 420, height: 480)
    }

    @ViewBuilder
    private func resultPane(title: String, time: String, text: String, placeholder: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if !time.isEmpty {
                    Text(time)
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(time == "—" ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.green))
                }
            }
            ScrollView {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quinary, in: .rect(cornerRadius: 8))
        }
    }

    private var buttonTitle: String {
        switch model.phase {
        case .idle: return "Record"
        case .preparing: return "Preparing…"
        case .recording: return "Stop & Transcribe"
        case .transcribing: return "Transcribing…"
        }
    }
}
