//
//  Transcriber.swift
//  echo
//
//  Turns one recording into styled text using the engine selected in Settings.
//  Each dictation stays on that engine; failures never trigger a cloud fallback.
//

import AVFoundation
import Foundation
import os

final class Transcriber {
    private struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private let log = Logger(subsystem: "sabeel.echo", category: "transcriber")
    private let groq = GroqClient()
    private let local = LocalTranscriber()

    private var engine: TranscriptionEngine?
    private var localSession: Task<Void, Error>?

    /// Bounds local startup and finalization so a stalled system speech service
    /// cannot leave Echo stuck in its transcribing state.
    private static let localFinishTimeout: TimeInterval = 10

    /// Prepares the selected engine while the user speaks. Local transcription
    /// returns a handler for streaming live audio; Groq only needs prewarming.
    @MainActor
    func prepare() -> ((AVAudioPCMBuffer) -> Void)? {
        let settings = AppSettings.shared
        engine = settings.engine

        switch settings.engine {
        case .groq:
            groq.prewarm()
            return nil
        case .local:
            let language = settings.languageCode
            let vocabulary = settings.vocabularyTerms
            localSession = Task { [local] in
                try await local.startSession(languageCode: language, vocabulary: vocabulary)
            }
            return { [local] buffer in local.feed(buffer) }
        }
    }

    /// Finishes the prepared engine and applies the selected output style.
    @MainActor
    func finish(_ recording: URL) async throws -> String {
        guard let engine else {
            throw Failure(errorDescription: "Transcription wasn't ready")
        }
        self.engine = nil

        let raw: String
        switch engine {
        case .local:
            raw = try await finishLocalSession()
        case .groq:
            raw = try await transcribeWithGroq(recording)
        }
        return AppSettings.shared.style.postProcess(raw)
    }

    /// Abandons preparation when recording is cancelled or fails to start.
    @MainActor
    func cancel() {
        engine = nil
        guard let session = localSession else { return }
        localSession = nil

        // Let startup settle before cancelling so teardown cannot race setup.
        Task { [local] in
            _ = try? await session.value
            local.cancel()
        }
    }

    private func finishLocalSession() async throws -> String {
        guard let session = localSession else {
            throw Failure(errorDescription: "On-device transcription wasn't ready")
        }
        localSession = nil

        guard let text = await localTranscript(
            session: session,
            timeout: Self.localFinishTimeout
        ) else {
            log.error("local transcription failed or timed out")
            local.cancel()
            throw Failure(
                errorDescription: "On-device transcription failed — switch engines in Settings"
            )
        }
        return text
    }

    @MainActor
    private func transcribeWithGroq(_ recording: URL) async throws -> String {
        let settings = AppSettings.shared
        guard let key = settings.resolvedAPIKey else {
            log.error("transcribe skipped: no API key")
            throw Failure(errorDescription: "No API key — add one in Settings")
        }

        do {
            return try await groq.transcribe(
                fileURL: recording,
                key: key,
                model: settings.model.rawValue,
                language: settings.languageCode,
                prompt: settings.groqPrompt
            )
        } catch {
            log.error("Groq transcription failed: \(error.localizedDescription, privacy: .public)")
            throw Failure(errorDescription: Self.failureReason(for: error))
        }
    }

    /// Races local startup/finalization against a timeout. A task group cannot
    /// do this because awaiting `Task.value` ignores cancellation and would
    /// still wait for a stalled session while draining the group.
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

    /// Maps Groq and network failures to short messages that fit the overlay.
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

    /// Extracts Groq's `error.message`, truncated to fit the overlay.
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
}
