//
//  VocabularyView.swift
//  echo
//
//  A small panel (styled like the Debug window) for editing the vocabulary
//  hint sent to Groq as the transcription `prompt` — names, jargon, and
//  acronyms echo should spell correctly. Edits write straight through to
//  AppSettings, which persists them to UserDefaults.
//

import SwiftUI

struct VocabularyView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 16) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)

            Text("Custom Vocabulary")
                .font(.headline)

            Text("Names, jargon, and acronyms echo should spell correctly. Sent to Groq as a hint with every transcription.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $settings.vocabularyPrompt)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quinary, in: .rect(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if settings.vocabularyPrompt.isEmpty {
                        Text("e.g. echo, Groq, SwiftUI, Sabeel, kAXSelectedTextAttribute")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }

            Text("Groq caps this at 224 tokens (~150 words).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}
