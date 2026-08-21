//
//  HelpView.swift
//  echo
//
//  The help window shows shortcuts, styles, engines, and permission steps.
//  The window does not change settings.
//

import SwiftUI

struct HelpView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)

            Text("Use Echo")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Shortcuts") {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            shortcutRow("Hold Fn", "Echo starts dictation while you hold the key. Echo pastes the text when you release the key.")
                            shortcutRow("Esc", "Echo cancels dictation. Echo does not transcribe or paste the audio.")
                        }
                    }

                    section("Styles") {
                        Text("**Normal** adds capitalization and punctuation. Use this style for email and documents.")
                        Text("**Lower Case** uses lowercase text. Use this style for chat.")
                        Text("Both styles use digits for numbers, such as “3 PM,” “$12,500,” and “room 204.”")
                            .foregroundStyle(.secondary)
                    }

                    section("Engines") {
                        Text("**On-device** uses Apple’s speech model on your Mac. This engine does not send audio over the internet.")
                        Text("**Groq** sends audio to a Whisper model in the cloud. This engine needs an internet connection.")
                        Text("Echo uses only the selected engine. If the selected engine does not work, select the other engine from the menu bar.")
                            .foregroundStyle(.secondary)
                        Text("Echo stores your Groq API key in macOS Keychain. To change the key, select Settings → Groq API Key.")
                            .foregroundStyle(.secondary)
                    }

                    section("Permissions") {
                        Text("Echo needs Microphone and Accessibility permissions. Manage these permissions in System Settings → Privacy & Security.")
                        Text("**Microphone** lets Echo record your speech. If a transcript is empty, check this permission.")
                        Text("**Accessibility** lets Echo detect the Fn key and paste text. Echo cannot do these actions without this permission.")
                        Text("If Echo does not have both permissions, use Settings → Request Permissions to grant both permissions.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(width: 440, height: 480)
    }

    /// This view shows a small title above its content.
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
