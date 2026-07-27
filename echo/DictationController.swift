//
//  DictationController.swift
//  echo
//
//  Ties the Fn hotkey to the complete dictation flow:
//  hold Fn → record → transcribe with the selected engine → paste.
//

import AppKit
import os

@MainActor
@Observable
final class DictationController {
    enum Phase: Equatable { case idle, recording, transcribing, error }

    static let shared = DictationController()

    @ObservationIgnored private let log = Logger(subsystem: "sabeel.echo", category: "dictation")
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let transcriber = Transcriber()
    @ObservationIgnored private let hotkey = FnHotkeyMonitor()
    @ObservationIgnored private lazy var overlay = RecordingOverlay(controller: self)

    /// Holds shorter than this are treated as accidental Fn taps.
    private static let minimumHold: TimeInterval = 0.3

    /// How long the overlay's error state stays visible.
    private static let errorFlashDuration: TimeInterval = 2.5

    /// Keeps macOS from throttling a dictation while Echo is in the background.
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var recordingStartedAt: Date?

    private(set) var phase: Phase = .idle
    private(set) var errorReason: String = ""

    func start() {
        hotkey.onPress = { [weak self] in self?.beginRecording() }
        hotkey.onRelease = { [weak self] in self?.finishRecording() }
        hotkey.onCancel = { [weak self] in self?.cancelRecording() }
        hotkey.start()
    }

    private func beginRecording() {
        guard phase == .idle else { return }
        beginActivity()

        let settings = AppSettings.shared
        recorder.onBuffer = transcriber.prepare()

        do {
            try recorder.start(inputDeviceUID: settings.inputDeviceUID)
            recordingStartedAt = Date()
            phase = .recording
            overlay.show()
            log.info("Recording started (Fn down, \(settings.engine.rawValue, privacy: .public))")
        } catch {
            log.error("record start failed: \(error.localizedDescription, privacy: .public)")
            recorder.onBuffer = nil
            transcriber.cancel()
            Task { await flashError("Couldn't start recording — check microphone access") }
        }
    }

    private func finishRecording() {
        guard phase == .recording else { return }

        let held = Date().timeIntervalSince(recordingStartedAt ?? .distantPast)
        guard held >= Self.minimumHold else {
            log.info("Hold too short (\(held, privacy: .public)s) — discarding")
            discardRecording()
            return
        }

        let recording = recorder.stop()
        recorder.onBuffer = nil
        guard let recording else {
            transcriber.cancel()
            reset()
            return
        }

        phase = .transcribing
        log.info("Recording stopped (Fn up) — transcribing")
        Task { await transcribeAndPaste(recording) }
    }

    private func transcribeAndPaste(_ recording: URL) async {
        defer { try? FileManager.default.removeItem(at: recording) }
        let startedAt = Date()

        let text: String
        do {
            text = try await transcriber.finish(recording)
        } catch {
            log.error("transcription failed: \(error.localizedDescription, privacy: .public)")
            await flashError(error.localizedDescription)
            return
        }

        let latency = Date().timeIntervalSince(startedAt)
        guard !text.isEmpty else {
            log.info("empty transcript — nothing to paste")
            await flashError("No speech detected")
            return
        }

        log.info("Transcribed in \(latency, privacy: .public)s: \(text, privacy: .private)")
        AppSettings.shared.recordTranscription(text, latency: latency)

        // Hide Echo before inserting into the field that was previously focused.
        phase = .idle
        overlay.hide()
        guard await Paster.paste(text) else {
            log.error("paste failed — transcript left on clipboard")
            await flashError("Couldn't paste — transcript is on the clipboard")
            return
        }
        reset()
    }

    private func cancelRecording() {
        guard phase == .recording else { return }
        log.info("Recording cancelled (Esc)")
        discardRecording()
    }

    private func discardRecording() {
        let recording = recorder.stop()
        recorder.onBuffer = nil
        transcriber.cancel()
        if let recording { try? FileManager.default.removeItem(at: recording) }
        reset()
    }

    private func flashError(_ reason: String) async {
        errorReason = reason
        phase = .error
        overlay.show()
        try? await Task.sleep(for: .seconds(Self.errorFlashDuration))
        reset()
    }

    private func reset() {
        recordingStartedAt = nil
        phase = .idle
        overlay.hide()
        endActivity()
    }

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
}
