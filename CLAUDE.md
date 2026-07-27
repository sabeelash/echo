# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**echo** is a macOS transcription app (bundle ID `sabeel.echo`) built with SwiftUI, targeting macOS 26.5+, written in Swift 5. Hold Fn, speak, and the app transcribes on-device or through Groq before pasting into the focused field.

## Building & Running

Open `echo.xcodeproj` in Xcode, select the `echo` scheme, and press ⌘R. There is no CLI build system — all building, running, and testing is done through Xcode or `xcodebuild`.

```bash
# Build from CLI
xcodebuild -project echo.xcodeproj -scheme echo -configuration Debug build

```

## Tech Stack

| Concern | Choice |
|---|---|
| UI | SwiftUI for all screens (settings, setup wizard, menu bar dropdown); `NSPanel` + `NSHostingView` for the recording overlay |
| Settings | Menu-bar controls backed by `AppSettings` |
| Audio capture | `AVAudioEngine` |
| Global hotkey | `NSEvent` monitors for the Fn modifier |
| Transcription | Apple Speech framework on-device, with Groq fallback |
| Persistence | `UserDefaults` for settings; Keychain for the Groq API key |
| Concurrency | Swift structured concurrency (`async`/`await` and `Task`) |

## Speed Optimizations

These are the techniques that make echo faster than alternatives:

- Encode audio as **M4A (AAC)** instead of WAV before upload
- **Pre-warm the HTTP connection** to Groq during recording (before the user finishes speaking)
- Send a **`language` hint** in the Groq request when the user selects one
- **Paste via Accessibility API** (`AXUIElementSetAttributeValue`) where the focused element supports it, preserving the clipboard
- Declare a **critical process activity** in macOS during dictation to prevent throttling

Evaluated and **dropped** (see `status.md` → Speed optimizations for the numbers):
- ~~Time-stretch audio to 1.5× speed before upload~~ — adds ~100–300ms of offline render + re-encode to save ~17ms; net loss.
- ~~Voice activity detection (VAD) trim before upload~~ — saves ~2ms and forces a re-encode onto the critical path; net loss.
- Both attack inference time, but Groq turbo (~200× real-time) makes inference ~50ms — not the bottleneck. The dominant slice is **network RTT + request overhead**.

## Architecture

The app is a fresh SwiftUI project with the standard Xcode template structure:

- **`echo/echoApp.swift`** — `@main` entry point, menu-bar scene, and utility windows
- **`echo/ContentView.swift`** — menu-bar controls

## Reference Apps

- [Freeflow](https://github.com/zachlatta/freeflow)
- [Handy](https://github.com/cjpais/Handy)
