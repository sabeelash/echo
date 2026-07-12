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

            Text("How echo works")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Shortcuts") {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            shortcutRow("Hold Fn", "Dictate — speak while holding, release to paste.")
                            shortcutRow("Esc", "Cancel a dictation mid-hold. Nothing is transcribed.")
                        }
                    }

                    section("Styles") {
                        Text("**Professional** — clean sentences with proper capitalization and punctuation. Great for email and docs.")
                        Text("**Casual** — relaxed, all-lowercase. Made for chat.")
                        Text("Both write numbers as digits — “3pm”, “$12,500”, “room 204”.")
                            .foregroundStyle(.secondary)
                    }

                    section("Engines") {
                        Text("**On-device** — Apple's speech model, running entirely on your Mac. No network round-trip, so it's the fastest option, and your audio never leaves the machine.")
                        Text("**Groq** — Whisper in the cloud. Extremely accurate and still quick; needs an internet connection.")
                        Text("If an on-device dictation ever fails, echo quietly retries the same audio through Groq — you just get your text.")
                            .foregroundStyle(.secondary)
                        Text("Heads-up: Groq currently runs on a built-in API key. A bring-your-own-key setting is on the way.")
                            .foregroundStyle(.secondary)
                    }

                    section("Permissions") {
                        Text("echo needs two permissions, both under System Settings → Privacy & Security:")
                        Text("**Microphone** — to hear you. If recordings come back empty, check this first.")
                        Text("**Accessibility** — powers the Fn hotkey and instant paste. Without it, the hotkey stops responding and pasting silently falls back or fails.")
                        Text("Fastest fix: choose Settings → Request Permissions from the menu bar and grant both.")
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
