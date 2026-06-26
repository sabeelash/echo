//
//  GroqClient.swift
//  echo
//
//  Minimal client for Groq's OpenAI-compatible audio transcription endpoint.
//  The API key is read from the GROQ_KEY environment variable (set in the
//  Xcode scheme for now; will move to the Keychain later).
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
            return "GROQ_KEY environment variable is not set."
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
    // Fastest Whisper variant Groq offers — speed is the whole point.
    private let model = "whisper-large-v3-turbo"

    private struct TranscriptionResponse: Decodable { let text: String }

    /// Uploads an audio file and returns the transcript text.
    func transcribe(fileURL: URL, language: String = "en") async throws -> String {
        guard let key = ProcessInfo.processInfo.environment["GROQ_KEY"], !key.isEmpty else {
            throw GroqError.missingKey
        }

        let audio = try Data(contentsOf: fileURL)
        let boundary = "echo-\(UUID().uuidString)"

        var body = Data()
        func textField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        // Audio part.
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        body.append("Content-Type: audio/m4a\r\n\r\n")
        body.append(audio)
        body.append("\r\n")

        // Always send a language hint — skips Groq's auto-detect pass.
        textField("model", model)
        textField("language", language)
        textField("response_format", "json")
        body.append("--\(boundary)--\r\n")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        Self.log.info("POST \(model, privacy: .public) — \(audio.count, privacy: .public) bytes of audio")
        let (data, response) = try await URLSession.shared.data(for: request)

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
