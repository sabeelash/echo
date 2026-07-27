//
//  TranscriptionOptions.swift
//  echo
//
//  The small set of opinionated transcription choices Echo exposes.
//

import Foundation

enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case local
    case groq

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "On-device"
        case .groq: return "Groq"
        }
    }
}

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

struct TranscriptionLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }

    static let auto = TranscriptionLanguage(code: "", name: "Auto-detect")

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

enum TranscriptionStyle: String, CaseIterable, Identifiable {
    case professional
    case casual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .professional: return "Normal"
        case .casual: return "Lower Case"
        }
    }

    /// Whisper mimics the prompt's style rather than obeying instructions.
    var exemplar: String {
        switch self {
        case .professional:
            return "The following is a professional transcript with proper capitalization, punctuation, and complete sentences. The meeting starts at 3pm, the budget is $12,500, and we are in room 204."
        case .casual:
            return "here's a casual transcript with no capitalization and relaxed punctuation just lowercase text. i'll grab 2 coffees and meet you at 5"
        }
    }

    func postProcess(_ text: String) -> String {
        switch self {
        case .professional: return text
        case .casual: return text.lowercased()
        }
    }
}
