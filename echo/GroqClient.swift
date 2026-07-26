//
//  GroqClient.swift
//  echo
//
//  Minimal client for Groq's OpenAI-compatible audio transcription endpoint.
//  The API key, model, and language come from AppSettings (with the key stored
//  securely in macOS Keychain).
//

import Foundation
import os

enum GroqError: Error, LocalizedError {
    case missingKey
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No Groq API key — add one in Settings."
        case .http(let code, let body):
            return "Groq HTTP \(code): \(body)"
        case .badResponse:
            return "Could not decode the Groq response."
        }
    }
}

struct GroqClient {
    private static let log = Logger(subsystem: "sabeel.echo", category: "groq")

    private let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!

    private struct TranscriptionResponse: Decodable { let text: String }

    /// Opens a TLS/TCP connection to Groq ahead of the upload so the POST that
    /// follows reuses a warm socket from `URLSession.shared`'s pool instead of
    /// paying the handshake (~2-3 round trips) on the critical path after the
    /// user releases Fn. Fire-and-forget: a HEAD to the endpoint 405s, but the
    /// connection it establishes is what we're after, so the result is ignored.
    func prewarm() {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
        Self.log.debug("prewarming Groq connection")
    }

    /// Uploads an audio file and returns the transcript text.
    /// `language` is an ISO-639-1 code; pass "" to let Groq auto-detect.
    /// `prompt` biases spelling/style toward provided terms (names, jargon);
    /// Groq caps it at 224 tokens. Pass "" to omit it.
    func transcribe(
        fileURL: URL,
        key: String,
        model: String = GroqModel.turbo.rawValue,
        language: String = "en",
        prompt: String = ""
    ) async throws -> String {
        guard !key.isEmpty else { throw GroqError.missingKey }

        let boundary = "echo-\(UUID().uuidString)"

        // Assemble the multipart body on disk and upload it from the file, so the
        // audio is streamed through a small buffer rather than held in memory
        // twice (once as Data, once copied into the request body).
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-body-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        guard FileManager.default.createFile(atPath: bodyURL.path, contents: nil) else {
            throw GroqError.badResponse
        }
        let out = try FileHandle(forWritingTo: bodyURL)
        defer { try? out.close() }

        func write(_ string: String) throws {
            if let d = string.data(using: .utf8) { try out.write(contentsOf: d) }
        }
        func textField(_ name: String, _ value: String) throws {
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            try write("\(value)\r\n")
        }

        // Audio part header, then the file streamed in chunks.
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        try write("Content-Type: audio/m4a\r\n\r\n")

        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try out.write(contentsOf: chunk)
        }
        try input.close()
        try write("\r\n")

        try textField("model", model)
        // A language hint skips Groq's auto-detect pass (faster); empty == auto.
        if !language.isEmpty { try textField("language", language) }
        // Vocabulary hint to bias spelling of names/jargon; empty == omit.
        if !prompt.isEmpty { try textField("prompt", prompt) }
        try textField("response_format", "json")
        try write("--\(boundary)--\r\n")
        try out.close()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let bodySize = (try? FileManager.default.attributesOfItem(atPath: bodyURL.path)[.size] as? Int) ?? nil
        Self.log.info("POST \(model, privacy: .public) — \(bodySize ?? -1, privacy: .public) bytes (multipart body)")
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)

        guard let http = response as? HTTPURLResponse else { throw GroqError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw GroqError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
            throw GroqError.badResponse
        }
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
