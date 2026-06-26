//
//  DictationController.swift
//  echo
//
//  Ties the Fn hotkey to the record → transcribe round-trip and drives the
//  recording overlay. Hold Fn to record; release to stop and transcribe.
//  For now the transcript is printed to the console (paste-into-field is a
//  later stage); the round-trip itself is the same one proven in stage 1.
//

import AppKit
import os

@MainActor
@Observable
final class DictationController {
    enum Phase: Equatable { case idle, recording, transcribing }

    static let shared = DictationController()

    @ObservationIgnored private let log = Logger(subsystem: "sabeel.echo", category: "dictation")
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let groq = GroqClient()
    @ObservationIgnored private let hotkey = FnHotkeyMonitor()
    @ObservationIgnored private lazy var overlay = RecordingOverlay(controller: self)

    private(set) var phase: Phase = .idle

    /// SF Symbol for the menu bar icon, reflecting the current phase.
    var menuBarSymbol: String {
        switch phase {
        case .idle: return "waveform.and.mic"
        case .recording: return "record.circle"
        case .transcribing: return "ellipsis.circle"
        }
    }

    func start() {
        hotkey.onPress = { [weak self] in self?.beginRecording() }
        hotkey.onRelease = { [weak self] in self?.endRecording() }
        hotkey.start()
    }

    private func beginRecording() {
        guard phase == .idle else { return }
        do {
            try recorder.start(inputDeviceUID: AppSettings.shared.inputDeviceUID)
            phase = .recording
            overlay.show()
            log.info("Recording started (Fn down)")
        } catch {
            log.error("record start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func endRecording() {
        guard phase == .recording else { return }
        guard let url = recorder.stop() else {
            phase = .idle
            overlay.hide()
            return
        }
        phase = .transcribing
        log.info("Recording stopped (Fn up) — transcribing")

        let settings = AppSettings.shared
        guard let key = settings.resolvedAPIKey else {
            print("❌ Transcription failed: no Groq API key — add one in Settings.")
            log.error("transcribe skipped: no API key")
            phase = .idle
            overlay.hide()
            return
        }
        let model = settings.model.rawValue
        let language = settings.languageCode

        Task {
            let text: String
            do {
                let start = Date()
                text = try await groq.transcribe(
                    fileURL: url, key: key, model: model, language: language
                )
                let dt = Date().timeIntervalSince(start)
                print(String(format: "📝 [%.2fs] %@", dt, text))
                log.info("Transcript: \(text, privacy: .public)")
                AppSettings.shared.recordTranscription(text, latency: dt)
            } catch {
                print("❌ Transcription failed: \(error.localizedDescription)")
                log.error("transcribe failed: \(error.localizedDescription, privacy: .public)")
                phase = .idle
                overlay.hide()
                return
            }
            // Dismiss the overlay before pasting so it isn't the focused-app's
            // concern, then insert into whatever field the user had focused.
            phase = .idle
            overlay.hide()
            await Paster.paste(text)
        }
    }
}
