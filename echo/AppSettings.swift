//
//  AppSettings.swift
//  echo
//
//  Single source of truth for user-configurable settings. Language and model
//  persist to UserDefaults and are toggled from the menu bar. The Groq API key
//  is stored separately in macOS Keychain.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let engine = "engine"
        static let languageCode = "languageCode"
        static let model = "model"
        static let inputDeviceUID = "inputDeviceUID"
        static let vocabularyPrompt = "vocabularyPrompt"
        static let style = "style"
        static let totalWords = "totalWords"
    }

    private let defaults: UserDefaults

    /// Groq (cloud) vs on-device transcription. Persisted.
    var engine: TranscriptionEngine {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine) }
    }

    /// ISO-639-1 code, or "" for auto-detect.
    var languageCode: String {
        didSet { defaults.set(languageCode, forKey: Keys.languageCode) }
    }

    var model: GroqModel {
        didSet { defaults.set(model.rawValue, forKey: Keys.model) }
    }

    /// Stable UID of the chosen input device; nil means the system default.
    var inputDeviceUID: String? {
        didSet { defaults.set(inputDeviceUID, forKey: Keys.inputDeviceUID) }
    }

    /// Optional vocabulary hint sent to Groq as the `prompt` field — names,
    /// jargon, and acronyms echo should spell correctly. Groq caps it at 224
    /// tokens; empty omits it. Persisted.
    var vocabularyPrompt: String {
        didSet { defaults.set(vocabularyPrompt, forKey: Keys.vocabularyPrompt) }
    }

    /// Casual vs. professional output styling. Persisted.
    var style: TranscriptionStyle {
        didSet { defaults.set(style.rawValue, forKey: Keys.style) }
    }

    /// The full `prompt` echo sends to Groq: the user's vocabulary terms (if
    /// any) followed by the selected style's exemplar, which Whisper mimics.
    var groqPrompt: String {
        let vocab = vocabularyPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return [vocab, style.exemplar].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The vocabulary as individual terms, for the local engine's
    /// `AnalysisContext.contextualStrings` (which wants an array, not prose).
    /// Split on commas/newlines only, so multi-word names survive intact.
    var vocabularyTerms: [String] {
        vocabularyPrompt
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Most recent successful transcript, surfaced by the menu's "Copy Last
    /// Transcript". Runtime-only — intentionally not persisted.
    var lastTranscript: String = ""

    /// Lifetime count of words dictated.
    private(set) var totalWords: Int

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.engine = defaults.string(forKey: Keys.engine)
            .flatMap(TranscriptionEngine.init(rawValue:)) ?? .local
        self.languageCode = defaults.string(forKey: Keys.languageCode) ?? "en"
        self.model = defaults.string(forKey: Keys.model)
            .flatMap(GroqModel.init(rawValue:)) ?? .turbo
        self.inputDeviceUID = defaults.string(forKey: Keys.inputDeviceUID)
        self.vocabularyPrompt = defaults.string(forKey: Keys.vocabularyPrompt) ?? ""
        self.style = defaults.string(forKey: Keys.style)
            .flatMap(TranscriptionStyle.init(rawValue:)) ?? .professional
        self.totalWords = defaults.integer(forKey: Keys.totalWords)
    }

    /// Stores the latest transcript and adds it to the lifetime word count.
    func recordTranscription(_ text: String) {
        lastTranscript = text
        totalWords += text.split(whereSeparator: \.isWhitespace).count
        defaults.set(totalWords, forKey: Keys.totalWords)
    }

    /// The Keychain-backed key the network layer should use.
    var resolvedAPIKey: String? {
        try? APIKeyStore.load()
    }
}
