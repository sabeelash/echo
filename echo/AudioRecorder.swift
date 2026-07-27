//
//  AudioRecorder.swift
//  echo
//
//  Captures microphone audio with AVAudioEngine and writes it straight to an
//  M4A (AAC) file. Encoding to AAC up front (rather than WAV) keeps the upload
//  small, which is one of the speed wins echo relies on.
//
//  Capture is downsampled to 16 kHz mono at a low bitrate before encoding:
//  Whisper resamples everything to 16 kHz mono internally, so the hardware's
//  48 kHz/stereo/high-quality stream is pure upload weight thrown away on the
//  far end. A 16 kHz mono 32 kbps file is several times smaller — a smaller,
//  faster upload (the dominant slice of the round-trip) with no accuracy loss.
//

import AVFoundation
import AudioToolbox
import os

final class AudioRecorder {
    enum RecorderError: LocalizedError {
        case alreadyRecording
        case formatUnavailable

        var errorDescription: String? {
            switch self {
            case .alreadyRecording:
                return "A recording is already in progress."
            case .formatUnavailable:
                return "The microphone's audio format is unavailable."
            }
        }
    }

    private let log = Logger(subsystem: "sabeel.echo", category: "recorder")
    private var engine = AVAudioEngine()
    private var file: AVAudioFile?
    /// Resamples the hardware tap buffers down to the file's 16 kHz mono format.
    private var converter: AVAudioConverter?
    private var configurationObserver: NSObjectProtocol?
    private var tapInstalled = false
    private var engineInvalidated = false
    private let interruptionState = OSAllocatedUnfairLock(initialState: false)

    private(set) var outputURL: URL?
    private(set) var isRecording = false

    /// Optional side-channel for raw hardware-format tap buffers, invoked on the
    /// audio tap thread while recording. Used by the on-device transcriber to
    /// stream audio into SpeechAnalyzer alongside the file write.
    var onBuffer: ((AVAudioPCMBuffer) -> Bool)?

    /// Called on the main queue when Core Audio invalidates an active recording.
    var onInterruption: () -> Void = {}

    /// Begins capturing into a fresh .m4a file in the temp dir. `inputDeviceUID`
    /// selects a specific mic by its Core Audio UID; nil uses the system default.
    func start(inputDeviceUID: String? = nil) throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }
        discardStaleState()

        interruptionState.withLock { $0 = false }
        engineInvalidated = false
        let activeEngine = engine

        do {
            let input = activeEngine.inputNode
            let selectedDevice = selectInputDevice(uid: inputDeviceUID, on: input)

            // A selected physical device exposes its hardware format on the
            // input bus. System Default stays nil so AVAudioEngine can finish
            // building its aggregate route before choosing the tap format.
            let format = selectedDevice
                ? input.inputFormat(forBus: 0)
                : input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw RecorderError.formatUnavailable
            }
            log.info("Input format before start: \(format.sampleRate, privacy: .public) Hz, \(format.channelCount, privacy: .public) ch")

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("echo-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
            ]

            let file = try AVAudioFile(forWriting: url, settings: settings)
            self.file = file
            outputURL = url

            input.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: selectedDevice ? format : nil
            ) {
                [weak self, weak activeEngine] buffer, _ in
                guard let self, let activeEngine else { return }

                let transcriberAccepted = self.onBuffer?(buffer) ?? true
                let recorderAccepted = self.append(buffer)
                if !transcriberAccepted || !recorderAccepted {
                    self.signalInterruption("Audio conversion failed", on: activeEngine)
                }
            }
            tapInstalled = true

            activeEngine.prepare()
            try activeEngine.start()
            guard activeEngine.isRunning else { throw RecorderError.formatUnavailable }

            isRecording = true
            observeConfigurationChanges(on: activeEngine)
            guard activeEngine.isRunning else { throw RecorderError.formatUnavailable }
            log.info("Recording → \(url.lastPathComponent, privacy: .public)")
        } catch {
            let partialRecording = tearDown(replaceEngine: true)
            if let partialRecording {
                try? FileManager.default.removeItem(at: partialRecording)
            }
            throw error
        }
    }

    /// Resamples one hardware tap buffer to the file's 16 kHz mono format and
    /// writes it. Runs on the audio tap thread.
    private func append(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let file else { return false }
        let target = file.processingFormat
        guard buffer.format.sampleRate > 0, buffer.format.channelCount > 0 else {
            log.error("Invalid input format")
            return false
        }

        if converter?.inputFormat != buffer.format {
            guard let converter = AVAudioConverter(from: buffer.format, to: target) else {
                log.error("No converter for \(buffer.format.sampleRate, privacy: .public) Hz, \(buffer.format.channelCount, privacy: .public) ch")
                return false
            }
            self.converter = converter
            log.info("Converter input → \(buffer.format.sampleRate, privacy: .public) Hz, \(buffer.format.channelCount, privacy: .public) ch")
        }
        guard let converter else { return false }

        // Output frame count shrinks with the sample-rate ratio; pad slightly.
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            return false
        }

        var fed = false
        var convError: NSError?
        let status = converter.convert(to: out, error: &convError) { _, inStatus in
            // Hand the converter this buffer once, then report no more input.
            if fed { inStatus.pointee = .noDataNow; return nil }
            fed = true
            inStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else {
            if let convError { log.error("Convert failed: \(convError.localizedDescription, privacy: .public)") }
            return false
        }
        guard out.frameLength > 0 else { return true }

        do {
            try file.write(from: out)
            return true
        } catch {
            log.error("Buffer write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func observeConfigurationChanges(on activeEngine: AVAudioEngine) {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: activeEngine,
            queue: nil
        ) { [weak self, weak activeEngine] _ in
            guard let self, let activeEngine else { return }
            self.signalInterruption("Audio engine configuration changed", on: activeEngine)
        }
    }

    /// Coalesces failures from Core Audio and the tap thread, then hands lifecycle
    /// work to the main queue. AVAudioEngine must not be destroyed in its own
    /// configuration-change notification callback.
    private func signalInterruption(_ reason: String, on activeEngine: AVAudioEngine) {
        let first = interruptionState.withLock { signaled -> Bool in
            guard !signaled else { return false }
            signaled = true
            return true
        }
        guard first else { return }

        log.error("\(reason, privacy: .public)")
        DispatchQueue.main.async { [weak self, weak activeEngine] in
            guard let self, let activeEngine else { return }
            guard self.engine === activeEngine, self.isRecording else { return }
            self.engineInvalidated = true
            self.onInterruption()
        }
    }

    /// Points the engine's input node at a specific device. No-op (system
    /// default) when `uid` is nil or the device isn't currently available.
    private func selectInputDevice(uid: String?, on input: AVAudioInputNode) -> Bool {
        guard let uid, let deviceID = AudioDevices.deviceID(forUID: uid) else { return false }
        guard let audioUnit = input.audioUnit else { return false }

        var device = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status == noErr {
            log.info("Input device → \(uid, privacy: .public)")
            return true
        } else {
            log.error("Failed to set input device (\(status, privacy: .public)); using default")
            return false
        }
    }

    /// Stops capture, finalizes the file, and returns its URL.
    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return nil }
        let recording = tearDown(replaceEngine: engineInvalidated)
        log.info("Stopped. File: \(recording?.lastPathComponent ?? "nil", privacy: .public)")
        return recording
    }

    /// Clears any partially-created state before a new transaction begins.
    private func discardStaleState() {
        guard tapInstalled || file != nil || outputURL != nil || configurationObserver != nil else {
            return
        }
        let staleRecording = tearDown(replaceEngine: true)
        if let staleRecording {
            try? FileManager.default.removeItem(at: staleRecording)
        }
    }

    /// Removes everything associated with the current recording. Abnormal
    /// teardown also replaces the engine so a poisoned graph cannot leak into
    /// the next Fn hold.
    private func tearDown(replaceEngine: Bool) -> URL? {
        let activeEngine = engine
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        if tapInstalled {
            activeEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        activeEngine.stop()
        if replaceEngine {
            activeEngine.reset()
            engine = AVAudioEngine()
        }

        let recording = outputURL
        file = nil
        converter = nil
        outputURL = nil
        isRecording = false
        engineInvalidated = false
        return recording
    }
}
