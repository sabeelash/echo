//
//  GroqClient.swift
//  echo
//
//  Minimal client for Groq's OpenAI-compatible audio transcription endpoint.
//  The API key, model, and language come from AppSettings (Keychain-backed
//  key, with a GROQ_KEY env-var fallback for the ⌘R dev flow).
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

    /// Uploads an audio file and returns the transcript text.
    /// `language` is an ISO-639-1 code; pass "" to let Groq auto-detect.
    func transcribe(
        fileURL: URL,
        key: String,
        model: String = GroqModel.turbo.rawValue,
        language: String = "en"
    ) async throws -> String {
        guard !key.isEmpty else { throw GroqError.missingKey }

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

        textField("model", model)
        // A language hint skips Groq's auto-detect pass (faster); empty == auto.
        if !language.isEmpty { textField("language", language) }
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
