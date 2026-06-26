//
//  AudioRecorder.swift
//  echo
//
//  Captures microphone audio with AVAudioEngine and writes it straight to an
//  M4A (AAC) file. Encoding to AAC up front (rather than WAV) keeps the upload
//  small, which is one of the speed wins echo relies on.
//
//  This is intentionally a simple start/stop recorder for the stage-1 debug
//  round-trip. The hotkey trigger (stage 2) will drive the same start()/stop().
//

import AVFoundation
import os

final class AudioRecorder {
    private let log = Logger(subsystem: "sabeel.echo", category: "recorder")
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?

    private(set) var outputURL: URL?
    private(set) var isRecording = false

    /// Begins capturing the default input into a fresh .m4a file in the temp dir.
    func start() throws {
        let input = engine.inputNode
        // The hardware input format — float PCM. AVAudioFile encodes these
        // buffers into AAC for us as we write them.
        let format = input.outputFormat(forBus: 0)
        log.info("Input format: \(format.sampleRate, privacy: .public) Hz, \(format.channelCount, privacy: .public) ch")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let file = try AVAudioFile(forWriting: url, settings: settings)
        self.file = file
        self.outputURL = url

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            do {
                try self?.file?.write(from: buffer)
            } catch {
                self?.log.error("Buffer write failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
        log.info("Recording → \(url.lastPathComponent, privacy: .public)")
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
        isRecording = false
        log.info("Stopped. File: \(self.outputURL?.lastPathComponent ?? "nil", privacy: .public)")
        return outputURL
    }
}
