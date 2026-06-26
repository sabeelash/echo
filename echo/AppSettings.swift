//
//  AppSettings.swift
//  echo
//
//  Single source of truth for user-configurable settings. Language and model
//  persist to UserDefaults and are toggled from the menu bar. The Groq API key
//  comes from the GROQ_KEY env var for now (no settings UI yet).
//

import Foundation
import Observation

/// The Groq Whisper variants echo can target. Raw value is the API model id.
enum GroqModel: String, CaseIterable, Identifiable {
    case turbo = "whisper-large-v3-turbo"
    case largeV3 = "whisper-large-v3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .turbo: return "Turbo — fastest"
        case .largeV3: return "Large v3 — most accurate"
        }
    }
}

/// A language echo can hint to Groq. `auto` omits the hint (Groq detects it,
/// at the cost of an extra pass — slower, so English is the default).
struct TranscriptionLanguage: Identifiable, Hashable {
    let code: String   // ISO-639-1, or "" for auto
    let name: String
    var id: String { code }

    static let auto = TranscriptionLanguage(code: "", name: "Auto-detect")

    /// Common picks up top; this isn't meant to be exhaustive.
    static let all: [TranscriptionLanguage] = [
        .auto,
        .init(code: "en", name: "English"),
        .init(code: "es", name: "Spanish"),
        .init(code: "fr", name: "French"),
        .init(code: "de", name: "German"),
        .init(code: "it", name: "Italian"),
        .init(code: "pt", name: "Portuguese"),
        .init(code: "nl", name: "Dutch"),
        .init(code: "hi", name: "Hindi"),
        .init(code: "ar", name: "Arabic"),
        .init(code: "zh", name: "Chinese"),
        .init(code: "ja", name: "Japanese"),
        .init(code: "ko", name: "Korean"),
        .init(code: "ru", name: "Russian"),
    ]
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let languageCode = "languageCode"
        static let model = "model"
        static let inputDeviceUID = "inputDeviceUID"
        static let transcriptionsToday = "transcriptionsToday"
        static let transcriptionsDate = "transcriptionsDate"
        static let totalWords = "totalWords"
    }

    private let defaults: UserDefaults

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

    /// Most recent successful transcript, surfaced by the menu's "Copy Last
    /// Transcript". Runtime-only — intentionally not persisted.
    var lastTranscript: String = ""

    /// Round-trip seconds of the most recent transcription (upload + inference).
    /// Runtime-only — a per-session speed readout, nil until the first dictation.
    var lastLatency: TimeInterval?

    /// Successful transcriptions so far today; rolls over at midnight. Persisted.
    private(set) var transcriptionsToday: Int

    /// Lifetime count of words dictated. Persisted vanity metric.
    private(set) var totalWords: Int

    /// The day `transcriptionsToday` belongs to, so we can reset across midnight.
    @ObservationIgnored private var countDate: Date

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.languageCode = defaults.string(forKey: Keys.languageCode) ?? "en"
        self.model = defaults.string(forKey: Keys.model)
            .flatMap(GroqModel.init(rawValue:)) ?? .turbo
        self.inputDeviceUID = defaults.string(forKey: Keys.inputDeviceUID)
        self.transcriptionsToday = defaults.integer(forKey: Keys.transcriptionsToday)
        self.totalWords = defaults.integer(forKey: Keys.totalWords)
        self.countDate = defaults.object(forKey: Keys.transcriptionsDate) as? Date ?? Date()
    }

    /// Record a successful transcription: stores it for "Copy Last Transcript",
    /// updates the latency readout, bumps today's count (resetting if the day
    /// rolled over), and adds to the lifetime word total.
    func recordTranscription(_ text: String, latency: TimeInterval) {
        lastTranscript = text
        lastLatency = latency

        if !Calendar.current.isDateInToday(countDate) {
            transcriptionsToday = 0
            countDate = Date()
            defaults.set(countDate, forKey: Keys.transcriptionsDate)
        }
        transcriptionsToday += 1
        defaults.set(transcriptionsToday, forKey: Keys.transcriptionsToday)

        totalWords += text.split(whereSeparator: \.isWhitespace).count
        defaults.set(totalWords, forKey: Keys.totalWords)
    }

    /// The key the network layer should use. Prefers a hardcoded key (personal
    /// use; works in an `open`ed .app), falling back to the GROQ_KEY env var
    /// from the Xcode scheme (⌘R only). Replace with Keychain later — see
    /// keychain-todo.md. Don't commit a real key.
    var resolvedAPIKey: String? {
        let hardcoded = "gsk_PASTE_YOUR_KEY_HERE"
        if !hardcoded.isEmpty, hardcoded != "gsk_PASTE_YOUR_KEY_HERE" {
            return hardcoded
        }
        let env = ProcessInfo.processInfo.environment["GROQ_KEY"]
        return (env?.isEmpty == false) ? env : nil
    }
}
