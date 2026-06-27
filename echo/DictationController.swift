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

    /// Token for the `beginActivity` that keeps macOS from throttling (App Nap)
    /// the audio engine / network mid-dictation. Held for the whole hold →
    /// transcribe → paste cycle; cleared on every exit path via `endActivity()`.
    @ObservationIgnored private var activity: NSObjectProtocol?

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
        beginActivity()
        // Warm the Groq connection now, while the user is still speaking, so the
        // upload on release reuses a live socket instead of handshaking first.
        groq.prewarm()
        do {
            try recorder.start(inputDeviceUID: AppSettings.shared.inputDeviceUID)
            phase = .recording
            overlay.show()
            log.info("Recording started (Fn down)")
        } catch {
            log.error("record start failed: \(error.localizedDescription, privacy: .public)")
            endActivity()
        }
    }

    /// Declares a latency-critical, user-initiated activity so macOS won't nap
    /// or throttle echo while it's recording/uploading in the background.
    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "echo dictation"
        )
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func endRecording() {
        guard phase == .recording else { return }
        guard let url = recorder.stop() else {
            phase = .idle
            overlay.hide()
            endActivity()
            return
        }
        phase = .transcribing
        log.info("Recording stopped (Fn up) — transcribing")

        let settings = AppSettings.shared
        guard let key = settings.resolvedAPIKey else {
            log.error("transcribe skipped: no API key")
            phase = .idle
            overlay.hide()
            endActivity()
            return
        }
        let model = settings.model.rawValue
        let language = settings.languageCode

        Task {
            // The recording is a single-use temp file; drop it once the upload
            // is done, on every exit path, so temp doesn't accumulate .m4a files.
            defer { try? FileManager.default.removeItem(at: url) }
            let text: String
            do {
                let start = Date()
                text = try await groq.transcribe(
                    fileURL: url, key: key, model: model, language: language
                )
                let dt = Date().timeIntervalSince(start)
                log.info("Transcribed in \(dt, privacy: .public)s: \(text, privacy: .private)")
                AppSettings.shared.recordTranscription(text, latency: dt)
            } catch {
                log.error("transcribe failed: \(error.localizedDescription, privacy: .public)")
                phase = .idle
                overlay.hide()
                endActivity()
                return
            }
            // Dismiss the overlay before pasting so it isn't the focused-app's
            // concern, then insert into whatever field the user had focused.
            phase = .idle
            overlay.hide()
            await Paster.paste(text)
            // Paste is the last step on the critical path — release the
            // anti-throttling activity now that the cycle is complete.
            endActivity()
        }
    }
}
