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
    enum Phase: Equatable { case idle, recording, transcribing, error }

    static let shared = DictationController()

    @ObservationIgnored private let log = Logger(subsystem: "sabeel.echo", category: "dictation")
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let groq = GroqClient()
    @ObservationIgnored private let local = LocalTranscriber()
    @ObservationIgnored private let hotkey = FnHotkeyMonitor()
    @ObservationIgnored private lazy var overlay = RecordingOverlay(controller: self)

    /// In-flight startup of the on-device session, kicked off at Fn-down.
    /// nil when the current dictation is using Groq.
    @ObservationIgnored private var localSession: Task<Void, Error>?

    /// How long Fn-up waits for the on-device engine — session startup (on
    /// first use that includes the model download) plus finalization — before
    /// giving up and falling back to Groq. Without a bound, a hang here would
    /// wedge `phase` at .transcribing and disable dictation until relaunch.
    private static let localFinishTimeout: TimeInterval = 10

    /// Holds shorter than this are treated as accidental Fn taps: the recording
    /// is discarded instead of burning a round-trip and pasting garbage.
    private static let minimumHold: TimeInterval = 0.3

    /// How long the overlay's red error state stays up before dismissing —
    /// long enough to read the failure reason, short enough not to nag.
    private static let errorFlashDuration: TimeInterval = 2.5

    /// Token for the `beginActivity` that keeps macOS from throttling (App Nap)
    /// the audio engine / network mid-dictation. Held for the whole hold →
    /// transcribe → paste cycle; cleared on every exit path via `endActivity()`.
    @ObservationIgnored private var activity: NSObjectProtocol?

    /// When the current hold started, for the accidental-tap check on release.
    @ObservationIgnored private var recordingStartedAt: Date?

    private(set) var phase: Phase = .idle

    /// Why the current `.error` flash is up, worded for the user. Shown in the
    /// overlay and menu bar in place of a bare "Failed".
    private(set) var errorReason: String = ""

    func start() {
        hotkey.onPress = { [weak self] in self?.beginRecording() }
        hotkey.onRelease = { [weak self] in self?.endRecording() }
        hotkey.onCancel = { [weak self] in self?.cancelRecording() }
        hotkey.start()
    }

    private func beginRecording() {
        guard phase == .idle else { return }
        beginActivity()
        let settings = AppSettings.shared
        switch settings.engine {
        case .groq:
            // Warm the Groq connection now, while the user is still speaking, so
            // the upload on release reuses a live socket instead of handshaking.
            groq.prewarm()
        case .local:
            // Recording starts immediately; the transcriber holds early tap
            // buffers until the model session is up, so no speech is lost.
            recorder.onBuffer = { [local] in local.feed($0) }
            let language = settings.languageCode
            let vocabulary = settings.vocabularyTerms
            localSession = Task { [local] in
                try await local.startSession(languageCode: language, vocabulary: vocabulary)
            }
        }
        do {
            try recorder.start(inputDeviceUID: settings.inputDeviceUID)
            recordingStartedAt = Date()
            phase = .recording
            overlay.show()
            log.info("Recording started (Fn down, \(settings.engine.rawValue, privacy: .public))")
        } catch {
            log.error("record start failed: \(error.localizedDescription, privacy: .public)")
            abandonLocalSession()
            // flashError ends the activity once the flash dismisses.
            Task { await flashError("Couldn't start recording — check microphone access") }
        }
    }

    /// Tears down an in-flight local session on paths that won't transcribe.
    /// Waits for startup to settle first so the cancel doesn't race it.
    private func abandonLocalSession() {
        recorder.onBuffer = nil
        guard let session = localSession else { return }
        localSession = nil
        abandonSettledSession(session)
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

    /// Esc pressed mid-hold: throw the recording away without transcribing.
    private func cancelRecording() {
        guard phase == .recording else { return }
        log.info("Recording cancelled (Esc)")
        discardRecording()
    }

    /// Stops the recorder and tears everything down without transcribing.
    /// Shared by Esc-cancel and the accidental-tap discard.
    private func discardRecording() {
        let session = localSession
        localSession = nil
        let url = recorder.stop()
        recorder.onBuffer = nil
        if let url { try? FileManager.default.removeItem(at: url) }
        abandonSettledSession(session)
        phase = .idle
        overlay.hide()
        endActivity()
    }

    private func endRecording() {
        guard phase == .recording else { return }

        // An Fn tap this short is almost certainly accidental — discard rather
        // than upload a fraction of a syllable and paste garbage.
        let held = Date().timeIntervalSince(recordingStartedAt ?? .distantPast)
        if held < Self.minimumHold {
            log.info("Hold too short (\(held, privacy: .public)s) — discarding")
            discardRecording()
            return
        }

        let session = localSession
        localSession = nil
        let url = recorder.stop()
        recorder.onBuffer = nil
        guard let url else {
            abandonSettledSession(session)
            phase = .idle
            overlay.hide()
            endActivity()
            return
        }
        phase = .transcribing
        log.info("Recording stopped (Fn up) — transcribing")

        let settings = AppSettings.shared
        let key = settings.resolvedAPIKey
        let model = settings.model.rawValue
        let language = settings.languageCode
        let prompt = settings.groqPrompt
        let style = settings.style

        Task {
            // The recording is a single-use temp file; drop it once transcription
            // is done, on every exit path, so temp doesn't accumulate .m4a files.
            defer { try? FileManager.default.removeItem(at: url) }
            let start = Date()
            var raw: String?

            // On-device first: the audio already streamed in during recording,
            // so this is just finalization. Any failure or timeout falls
            // through to Groq with the recorded file — same audio, slower
            // path, no lost speech.
            if let session {
                raw = await localTranscript(session: session, timeout: Self.localFinishTimeout)
                if raw == nil {
                    log.error("local transcription failed or timed out — falling back to Groq")
                    local.cancel()
                }
            }

            if raw == nil {
                guard let key else {
                    log.error("transcribe skipped: no API key")
                    await flashError(session != nil
                        ? "On-device engine failed — no API key to fall back to"
                        : "No API key — add one in Settings")
                    return
                }
                do {
                    raw = try await groq.transcribe(
                        fileURL: url, key: key, model: model, language: language, prompt: prompt
                    )
                } catch {
                    log.error("transcribe failed: \(error.localizedDescription, privacy: .public)")
                    await flashError(Self.failureReason(for: error))
                    return
                }
            }

            let text = style.postProcess(raw ?? "")
            let dt = Date().timeIntervalSince(start)
            guard !text.isEmpty else {
                log.info("empty transcript — nothing to paste")
                await flashError("No speech detected")
                return
            }
            log.info("Transcribed in \(dt, privacy: .public)s: \(text, privacy: .private)")
            AppSettings.shared.recordTranscription(text, latency: dt)
            // Dismiss the overlay before pasting so it isn't the focused-app's
            // concern, then insert into whatever field the user had focused.
            phase = .idle
            overlay.hide()
            guard await Paster.paste(text) else {
                // The transcript didn't land anywhere visible; Paster left it
                // on the clipboard, so tell the user ⌘V recovers it.
                log.error("paste failed — transcript left on clipboard")
                await flashError("Couldn't paste — transcript is on the clipboard")
                return
            }
            // Paste is the last step on the critical path — release the
            // anti-throttling activity now that the cycle is complete.
            endActivity()
        }
    }

    /// Fail loudly: hold the overlay in a red error state briefly before
    /// dismissing, so a failed dictation never just vanishes. While the flash
    /// is up `phase` is `.error`, which also blocks a new hold from starting.
    private func flashError(_ reason: String) async {
        errorReason = reason
        phase = .error
        overlay.show()
        try? await Task.sleep(for: .seconds(Self.errorFlashDuration))
        phase = .idle
        overlay.hide()
        endActivity()
    }

    /// Awaits local session startup + finalization, giving up after `timeout`
    /// seconds. Returns the transcript, or nil on failure/timeout. A task group
    /// can't race these (awaiting `Task.value` ignores cancellation, so a hung
    /// session would block the group's drain) — instead the first of
    /// {transcript, timeout} to land resumes the continuation and the loser's
    /// resume is dropped. A timed-out attempt keeps running in the background;
    /// the caller's `local.cancel()` unblocks it, and its result is discarded.
    private func localTranscript(session: Task<Void, Error>, timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let resumeOnce: @Sendable (String?) -> Void = { value in
                let first = resumed.withLock { done -> Bool in
                    let wasFirst = !done
                    done = true
                    return wasFirst
                }
                if first { continuation.resume(returning: value) }
            }
            Task { [local, log] in
                do {
                    try await session.value
                    resumeOnce(try await local.finish())
                } catch {
                    log.error("local transcription failed: \(error.localizedDescription, privacy: .public)")
                    resumeOnce(nil)
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                resumeOnce(nil)
            }
        }
    }

    /// Maps a transcription error to a short, user-facing reason for the error
    /// flash. Groq's own error message is surfaced when the body carries one;
    /// otherwise the status code / transport failure picks a category.
    private static func failureReason(for error: Error) -> String {
        switch error {
        case GroqError.missingKey:
            return "No API key — add one in Settings"
        case GroqError.badResponse:
            return "Unreadable response from Groq"
        case let GroqError.http(code, body):
            if let message = groqErrorMessage(from: body) { return message }
            switch code {
            case 401, 403: return "Invalid API key — check Settings"
            case 413: return "Recording too large for Groq"
            case 429: return "Rate limited by Groq — try again shortly"
            case 500...: return "Groq server error (HTTP \(code))"
            default: return "Groq request failed (HTTP \(code))"
            }
        case let urlError as URLError:
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "No internet connection"
            case .timedOut:
                return "Request timed out"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed:
                return "Can't reach Groq"
            default:
                return "Network error — try again"
            }
        default:
            return "Transcription failed"
        }
    }

    /// Pulls `error.message` out of a Groq error body (OpenAI-style
    /// `{"error":{"message":…}}`), truncated to fit the overlay.
    private static func groqErrorMessage(from body: String) -> String? {
        struct ErrorBody: Decodable {
            struct Inner: Decodable { let message: String }
            let error: Inner
        }
        guard let data = body.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ErrorBody.self, from: data) else { return nil }
        let message = decoded.error.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return nil }
        return message.count > 80 ? String(message.prefix(77)) + "…" : message
    }

    /// Fire-and-forget cleanup of a local session whose dictation was abandoned.
    private func abandonSettledSession(_ session: Task<Void, Error>?) {
        guard let session else { return }
        Task { [local] in
            _ = try? await session.value
            local.cancel()
        }
    }
}
