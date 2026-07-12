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

/// Which engine transcribes dictations. Groq is the cloud path (Whisper
/// large-v3, needs network + API key); local is the on-device SpeechAnalyzer
/// (macOS 26) — no network round-trip, so lower latency (see status.md).
enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case groq
    case local

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq: return "Groq — cloud"
        case .local: return "On-device — fastest"
        }
    }
}

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

/// Output style echo biases Groq toward. Whisper mimics the style of its
/// `prompt` rather than obeying instructions, so each case's `exemplar` is
/// written *in* the style it wants out — proper case + punctuation for
/// professional, all-lowercase for casual.
enum TranscriptionStyle: String, CaseIterable, Identifiable {
    case professional
    case casual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .professional: return "Professional"
        case .casual: return "Casual"
        }
    }

    /// Appended to the Groq `prompt` to steer capitalization/punctuation.
    /// Each exemplar also writes numbers as digits ("3pm", "$12,500") to bias
    /// Whisper toward numerals over spelled-out numbers — an orthogonal
    /// formatting axis folded into both styles rather than a style of its own.
    var exemplar: String {
        switch self {
        case .professional:
            return "The following is a professional transcript with proper capitalization, punctuation, and complete sentences. The meeting starts at 3pm, the budget is $12,500, and we are in room 204."
        case .casual:
            return "here's a casual transcript with no capitalization and relaxed punctuation just lowercase text. i'll grab 2 coffees and meet you at 5"
        }
    }

    /// Deterministic cleanup the prompt bias can't guarantee. Whisper keeps
    /// capitalizing "I" and proper nouns however the prompt is phrased, so
    /// casual force-lowercases the whole transcript; professional leaves
    /// Groq's output untouched.
    func postProcess(_ text: String) -> String {
        switch self {
        case .professional: return text
        case .casual: return text.lowercased()
        }
    }
}

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
        static let transcriptionsToday = "transcriptionsToday"
        static let transcriptionsDate = "transcriptionsDate"
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
        self.engine = defaults.string(forKey: Keys.engine)
            .flatMap(TranscriptionEngine.init(rawValue:)) ?? .groq
        self.languageCode = defaults.string(forKey: Keys.languageCode) ?? "en"
        self.model = defaults.string(forKey: Keys.model)
            .flatMap(GroqModel.init(rawValue:)) ?? .turbo
        self.inputDeviceUID = defaults.string(forKey: Keys.inputDeviceUID)
        self.vocabularyPrompt = defaults.string(forKey: Keys.vocabularyPrompt) ?? ""
        self.style = defaults.string(forKey: Keys.style)
            .flatMap(TranscriptionStyle.init(rawValue:)) ?? .professional
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

        rollOverDailyCountIfNeeded()
        transcriptionsToday += 1
        defaults.set(transcriptionsToday, forKey: Keys.transcriptionsToday)

        totalWords += text.split(whereSeparator: \.isWhitespace).count
        defaults.set(totalWords, forKey: Keys.totalWords)
    }

    /// Resets `transcriptionsToday` when the day has changed. Called before
    /// every bump, and by the menu when it opens — otherwise the count would
    /// show yesterday's number until the next dictation happened to roll it.
    func rollOverDailyCountIfNeeded() {
        guard !Calendar.current.isDateInToday(countDate) else { return }
        transcriptionsToday = 0
        countDate = Date()
        defaults.set(countDate, forKey: Keys.transcriptionsDate)
        defaults.set(transcriptionsToday, forKey: Keys.transcriptionsToday)
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
