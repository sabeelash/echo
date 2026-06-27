# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**echo** is a macOS transcription app (bundle ID `sabeel.echo`) built with SwiftUI, targeting macOS 26.5+, written in Swift 5. The goal is to be the fastest transcription app available — hold a hotkey (Fn), speak, and the transcribed text is pasted into the focused field as quickly as possible. Inference runs through Groq. The app is lightweight, minimal, and should feel like a native Apple app.

## Building & Running

Open `echo.xcodeproj` in Xcode, select the `echo` scheme, and press ⌘R. There is no CLI build system — all building, running, and testing is done through Xcode or `xcodebuild`.

```bash
# Build from CLI
xcodebuild -project echo.xcodeproj -scheme echo -configuration Debug build

# Run unit tests
xcodebuild test -project echo.xcodeproj -scheme echo -destination 'platform=macOS'

# Run a single test (by test identifier)
xcodebuild test -project echo.xcodeproj -scheme echo -destination 'platform=macOS' -only-testing:echoTests/echoTests/example
```

## Tech Stack

| Concern | Choice |
|---|---|
| UI | SwiftUI for all screens (settings, setup wizard, menu bar dropdown); `NSPanel` + `NSHostingView` for the recording overlay |
| Settings navigation | `NavigationSplitView` with `Form { Section { } }` |
| Audio capture | `AVAudioEngine` |
| Global hotkeys | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (Sindre Sorhus) — do not hand-roll Carbon event taps |
| Persistence | `UserDefaults` / `@AppStorage` for settings; Keychain for the Groq API key |
| Concurrency | Swift structured concurrency (`async/await`, `Task`, `TaskGroup`) throughout |

## Speed Optimizations

These are the techniques that make echo faster than alternatives:

- Encode audio as **M4A (AAC)** instead of WAV before upload
- **Pre-warm the HTTP connection** to Groq during recording (before the user finishes speaking)
- Always send a **`language` hint** in the Groq request
- **Paste via Accessibility API** (`AXUIElementSetAttributeValue`) where the focused element supports it — faster than clipboard
- Declare a **critical process activity** in macOS during dictation to prevent throttling
- Animate overlay dismissal after paste

Evaluated and **dropped** (see `status.md` → Speed optimizations for the numbers):
- ~~Time-stretch audio to 1.5× speed before upload~~ — adds ~100–300ms of offline render + re-encode to save ~17ms; net loss.
- ~~Voice activity detection (VAD) trim before upload~~ — saves ~2ms and forces a re-encode onto the critical path; net loss.
- Both attack inference time, but Groq turbo (~200× real-time) makes inference ~50ms — not the bottleneck. The dominant slice is **network RTT + request overhead**; the only unimplemented idea that targets it is **streaming/chunked upload during recording**.

## Architecture

The app is a fresh SwiftUI project with the standard Xcode template structure:

- **`echo/echoApp.swift`** — `@main` entry point, sets up the `WindowGroup` with `ContentView`
- **`echo/ContentView.swift`** — root SwiftUI view
- **`echoTests/`** — unit tests using Swift Testing (`import Testing`, `@Test` macros, `#expect(...)`)
- **`echoUITests/`** — UI tests using XCTest

Swift Testing (not XCTest) is used for unit tests — use `@Test` and `#expect(...)` rather than `XCTestCase`.

## Reference Apps

- [Freeflow](https://github.com/zachlatta/freeflow)
- [Handy](https://github.com/cjpais/Handy)
