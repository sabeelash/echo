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
    enum RecorderError: Error { case formatUnavailable }

    private let log = Logger(subsystem: "sabeel.echo", category: "recorder")
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    /// Resamples the hardware tap buffers down to the file's 16 kHz mono format.
    private var converter: AVAudioConverter?

    private(set) var outputURL: URL?
    private(set) var isRecording = false

    /// Begins capturing into a fresh .m4a file in the temp dir. `inputDeviceUID`
    /// selects a specific mic by its Core Audio UID; nil uses the system default.
    func start(inputDeviceUID: String? = nil) throws {
        let input = engine.inputNode
        // Route to the chosen device *before* reading the format — the format
        // (sample rate / channels) depends on which device is active.
        selectInputDevice(uid: inputDeviceUID, on: input)

        // The hardware input format — float PCM. AVAudioFile encodes these
        // buffers into AAC for us as we write them.
        let format = input.outputFormat(forBus: 0)
        log.info("Input format: \(format.sampleRate, privacy: .public) Hz, \(format.channelCount, privacy: .public) ch")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-\(UUID().uuidString).m4a")

        // 16 kHz mono AAC at 32 kbps: all Whisper needs, a fraction of the size.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]

        let file = try AVAudioFile(forWriting: url, settings: settings)
        self.file = file
        self.outputURL = url

        // The file expects buffers in its 16 kHz mono processing format, but the
        // tap delivers the hardware format — convert each buffer before writing.
        guard let converter = AVAudioConverter(from: format, to: file.processingFormat) else {
            throw RecorderError.formatUnavailable
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
        log.info("Recording → \(url.lastPathComponent, privacy: .public)")
    }

    /// Resamples one hardware tap buffer to the file's 16 kHz mono format and
    /// writes it. Runs on the audio tap thread.
    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let file else { return }
        let target = file.processingFormat

        // Output frame count shrinks with the sample-rate ratio; pad slightly.
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        var fed = false
        var convError: NSError?
        let status = converter.convert(to: out, error: &convError) { _, inStatus in
            // Hand the converter this buffer once, then report no more input.
            if fed { inStatus.pointee = .noDataNow; return nil }
            fed = true
            inStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0 else {
            if let convError { log.error("Convert failed: \(convError.localizedDescription, privacy: .public)") }
            return
        }
        do {
            try file.write(from: out)
        } catch {
            log.error("Buffer write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Points the engine's input node at a specific device. No-op (system
    /// default) when `uid` is nil or the device isn't currently available.
    private func selectInputDevice(uid: String?, on input: AVAudioInputNode) {
        guard let uid, let deviceID = AudioDevices.deviceID(forUID: uid) else { return }
        guard let audioUnit = input.audioUnit else { return }

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
        } else {
            log.error("Failed to set input device (\(status, privacy: .public)); using default")
        }
    }

    /// Stops capture, finalizes the file, and returns its URL.
    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return outputURL }
        // Order matters: remove the tap (stops callbacks) and stop the engine
        // before releasing the file so no buffer is written after finalize.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
        converter = nil
        isRecording = false
        log.info("Stopped. File: \(self.outputURL?.lastPathComponent ?? "nil", privacy: .public)")
        return outputURL
    }
}
