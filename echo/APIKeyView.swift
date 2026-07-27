//
//  APIKeyView.swift
//  echo
//
//  Small branded setup/settings panel for the user's Groq API key.
//

import SwiftUI

struct APIKeyView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var apiKey = ""
    @State private var hasSavedKey = false
    @State private var errorMessage: String?
    @FocusState private var keyFieldFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)

            Text(hasSavedKey ? "Groq API Key" : "Set Up Groq")
                .font(.headline)

            Text("Echo uses your Groq API key only when Groq is the selected transcription engine.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("gsk_…", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .focused($keyFieldFocused)
                .onSubmit(save)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(hasSavedKey
                     ? "Your key is stored securely in macOS Keychain."
                     : "Create or copy a key from the Groq console. It usually starts with gsk_.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if hasSavedKey {
                    Button("Remove Key", role: .destructive, action: remove)
                }

                Spacer()

                Button("Save Key", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 250)
        .onAppear(perform: load)
    }

    private func load() {
        do {
            apiKey = try APIKeyStore.load() ?? ""
            hasSavedKey = !apiKey.isEmpty
            errorMessage = nil
        } catch {
            apiKey = ""
            hasSavedKey = false
            errorMessage = error.localizedDescription
        }

        Task { @MainActor in
            await Task.yield()
            keyFieldFocused = true
        }
    }

    private func save() {
        do {
            try APIKeyStore.save(apiKey)
            errorMessage = nil
            dismissWindow(id: "api-key")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try APIKeyStore.delete()
            apiKey = ""
            hasSavedKey = false
            errorMessage = nil
            keyFieldFocused = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
