//
//  HelpView.swift
//  echo
//
//  A small reference panel (styled like the Vocabulary window): shortcuts,
//  what each style does, how the two engines relate, and permission
//  troubleshooting. Purely informational — nothing here writes settings.
//

import SwiftUI

struct HelpView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)

            Text("How Echo works")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Shortcuts") {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            shortcutRow("Hold Fn", "Dictate. Speak while you hold, release to paste.")
                            shortcutRow("Esc", "Cancel while dictating. Nothing is transcribed or pasted.")
                        }
                    }

                    section("Styles") {
                        Text("**Professional** — clean sentences with proper capitalization and punctuation. Suited to email and documents.")
                        Text("**Casual** — relaxed and all-lowercase, the way you'd type in chat.")
                        Text("Both styles write numbers as digits — “3pm”, “$12,500”, “room 204”.")
                            .foregroundStyle(.secondary)
                    }

                    section("Engines") {
                        Text("**On-device** — Apple's speech model, running entirely on your Mac. The fastest option — no network round-trip — and your audio never leaves the machine.")
                        Text("**Groq** — Whisper running in the cloud. Extremely accurate and still quick, but needs an internet connection.")
                        Text("If an on-device dictation fails, Echo automatically retries the same audio through Groq — you still get your text.")
                            .foregroundStyle(.secondary)
                        Text("Groq currently uses a built-in API key. A bring-your-own-key setting is on the way.")
                            .foregroundStyle(.secondary)
                    }

                    section("Permissions") {
                        Text("Echo needs two permissions, both in System Settings → Privacy & Security:")
                        Text("**Microphone** — so Echo can hear you. If dictations come back empty, check this first.")
                        Text("**Accessibility** — powers the Fn hotkey and instant paste. Without it, the hotkey won't respond and pasting can silently fail.")
                        Text("The quickest fix: choose Settings → Request Permissions from the menu bar and grant both.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(width: 440, height: 480)
    }

    /// A titled block: small secondary header above the content rows.
    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            content()
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortcutRow(_ key: String, _ action: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(key)
                .font(.callout.weight(.medium).monospaced())
            Text(action)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
