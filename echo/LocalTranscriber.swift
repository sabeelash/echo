//
//  LocalTranscriber.swift
//  echo
//
//  On-device transcription via the macOS 26 SpeechAnalyzer APIs. One instance
//  runs one streaming session at a time: `startSession` loads the model, `feed`
//  streams audio while the user speaks, and `finish` returns the transcript.
//
//  The model asset is downloaded and managed by the system (AssetInventory)
//  and inference runs out of process, so this adds nothing to echo's memory
//  footprint — the reason this route was chosen over WhisperKit on 8 GB machines.
//

import AVFoundation
import Speech
import os

final class LocalTranscriber {
    enum LocalError: Error, LocalizedError {
        case notAvailable
        case localeUnsupported(String)
        case noSession

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "SpeechTranscriber is not available on this system."
            case .localeUnsupported(let code):
                return "SpeechTranscriber does not support the language “\(code)”."
            case .noSession:
                return "No local transcription session is running."
            }
        }
    }

    private let log = Logger(subsystem: "sabeel.echo", category: "local")

    /// Guards everything below: `feed` runs on the audio tap thread while
    /// `startSession`/`finish`/`cancel` run on cooperative-pool threads.
    private let lock = NSLock()
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var resultsTask: Task<String, Error>?
    /// Tap buffers that arrived while the session was still starting (dictation
    /// begins recording immediately; the model takes a few hundred ms to come
    /// up). Flushed into the analyzer as soon as it's ready — no speech lost.
    private var pendingBuffers: [AVAudioPCMBuffer] = []
    private var sessionReady = false

    /// Creates the transcriber for `languageCode` (ISO-639-1, "" = system locale),
    /// downloads the model asset if this is the first use, preheats it, and starts
    /// the analyzer on a fresh input stream. Call before recording begins so model
    /// load time stays off the measured stop → transcript path.
    ///
    /// `vocabulary` biases recognition toward the given terms (names, jargon) —
    /// the local analogue of the Groq `prompt` — and picks the module:
    /// **SpeechTranscriber ignores `contextualStrings`** (framework limitation),
    /// so a non-empty vocabulary switches to DictationTranscriber, which honors
    /// them (measured: fixed every jargon term the default module misspelled).
    /// Empty vocabulary keeps SpeechTranscriber for its better baseline
    /// accuracy and punctuation.
    func startSession(languageCode: String, vocabulary: [String] = []) async throws {
        guard SpeechTranscriber.isAvailable else { throw LocalError.notAvailable }

        let requested = Locale(identifier: languageCode.isEmpty ? Locale.current.identifier : languageCode)
        let module: any SpeechModule
        let resultsTask: Task<String, Error>
        if vocabulary.isEmpty {
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
                throw LocalError.localeUnsupported(requested.identifier)
            }
            // fastResults biases the module toward low latency over batch
            // throughput.
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults, .fastResults],
                attributeOptions: []
            )
            module = transcriber
            resultsTask = Self.collect(transcriber.results.map { (String($0.text.characters), $0.isFinal) })
        } else {
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requested) else {
                throw LocalError.localeUnsupported(requested.identifier)
            }
            let transcriber = DictationTranscriber(
                locale: locale,
                contentHints: [.shortForm],
                transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults, .frequentFinalization],
                attributeOptions: []
            )
            module = transcriber
            resultsTask = Self.collect(transcriber.results.map { (String($0.text.characters), $0.isFinal) })
        }

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            log.info("downloading speech model assets for \(requested.identifier, privacy: .public)…")
            try await request.downloadAndInstall()
            log.info("speech model installed")
        }

        let context = AnalysisContext()
        if !vocabulary.isEmpty {
            context.contextualStrings = [.general: vocabulary]
        }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        // .processLifetime keeps the model warm across sessions, mirroring how
        // production would hold it between dictations. This init starts the
        // analyzer on the stream; no separate start call.
        let analyzer = SpeechAnalyzer(
            inputSequence: stream,
            modules: [module],
            options: .init(priority: .userInitiated, modelRetention: .processLifetime),
            analysisContext: context
        )
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
        try await analyzer.prepareToAnalyze(in: format)

        let held: [AVAudioPCMBuffer] = lock.withLock {
            self.analyzer = analyzer
            self.analyzerFormat = format
            self.inputBuilder = continuation
            self.resultsTask = resultsTask
            self.converter = nil
            let held = pendingBuffers
            pendingBuffers = []
            sessionReady = true
            for buffer in held { ingest(buffer) }
            return held
        }
        log.info("local session started (\(requested.identifier, privacy: .public), \(vocabulary.isEmpty ? "SpeechTranscriber" : "DictationTranscriber + \(vocabulary.count) vocab terms", privacy: .public), flushed \(held.count, privacy: .public) held buffers)")
    }

    /// Accumulates the finalized segments from a module's result stream.
    private static func collect<S: AsyncSequence & Sendable>(
        _ results: S
    ) -> Task<String, Error> where S.Element == (String, Bool) {
        Task {
            var finalized = ""
            for try await (text, isFinal) in results {
                if isFinal { finalized += text }
            }
            return finalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Streams one hardware-format tap buffer into the analyzer. Runs on the
    /// audio tap thread. Safe to call before the session is up — early buffers
    /// are held and flushed when `startSession` completes.
    func feed(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard sessionReady else {
            // ~85ms of audio per buffer at 48kHz/4096 frames; cap ≈ 25s so an
            // abandoned session can't accumulate audio forever.
            if pendingBuffers.count < 300 { pendingBuffers.append(buffer) }
            return
        }
        ingest(buffer)
    }

    /// Converts one buffer to the module's preferred format and yields it to
    /// the analyzer. Must be called with `lock` held.
    private func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let inputBuilder else { return }
        guard let analyzerFormat, analyzerFormat != buffer.format else {
            inputBuilder.yield(AnalyzerInput(buffer: buffer))
            return
        }
        if converter == nil {
            converter = AVAudioConverter(from: buffer.format, to: analyzerFormat)
        }
        guard let converter else { return }

        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }

        var fed = false
        var convError: NSError?
        let status = converter.convert(to: out, error: &convError) { _, inStatus in
            if fed { inStatus.pointee = .noDataNow; return nil }
            fed = true
            inStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0 else {
            if let convError { log.error("local convert failed: \(convError.localizedDescription, privacy: .public)") }
            return
        }
        inputBuilder.yield(AnalyzerInput(buffer: out))
    }

    /// Ends input, finalizes whatever the analyzer hasn't settled yet, and
    /// returns the full transcript. The interesting measurement is how long this
    /// takes: the audio already streamed in during recording.
    func finish() async throws -> String {
        let (analyzer, resultsTask, inputBuilder) = lock.withLock {
            (self.analyzer, self.resultsTask, self.inputBuilder)
        }
        guard let analyzer, let resultsTask else { throw LocalError.noSession }
        inputBuilder?.finish()
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let text = try await resultsTask.value
            teardown()
            return text
        } catch {
            // Tear down on failure too — otherwise the dead session lingers
            // and the next startSession replaces it while it's still "live".
            resultsTask.cancel()
            teardown()
            throw error
        }
    }

    /// Abandons the session (record-start failure, window closed mid-recording).
    func cancel() {
        lock.lock()
        let analyzer = self.analyzer
        let resultsTask = self.resultsTask
        let inputBuilder = self.inputBuilder
        lock.unlock()
        inputBuilder?.finish()
        resultsTask?.cancel()
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        teardown()
    }

    private func teardown() {
        lock.lock()
        analyzer = nil
        inputBuilder = nil
        analyzerFormat = nil
        converter = nil
        resultsTask = nil
        pendingBuffers = []
        sessionReady = false
        lock.unlock()
    }
}
