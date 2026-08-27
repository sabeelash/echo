<p align="center">
  <img src="docs/echo-logo.svg" width="360" alt="Echo logo and wordmark">
</p>

Echo is a fast, native macOS dictation app. Hold the `Fn` key, speak, and release
to paste the transcript into the field you were using. Think WhisprFlow or Monologue or Superhuman.

It runs quietly in the menu bar and supports both on-device transcription and
Groq's cloud-hosted Whisper models.

You'll need macOS 26.5 or later and if you are using the Groq's cloud-hosted Whisper models,
a Groq API key.

## Quick Start

1. Echo opens the Groq API key panel on first launch. The key is stored in macOS
Keychain and can be changed later from **Settings → Groq API Key…**.
2. Choose a transcription engine from the menu bar.
  - **On-device** streams audio through Apple's Speech framework for the lowest
  latency. This is the default.
  - **Groq** sends the recording to a selected Whisper model. Turbo favors speed;
  Large v3 favors accuracy.
3. Focus any editable text field.
4. Hold **Fn** and speak.
5. Release **Fn**.
6. Echo transcribes the recording and pastes the result at the cursor.

The menu bar also provides model, style (a lowercase version for casual texting), microphone, language,
vocabulary, and last-transcript controls.

## Distribution

The project is currently intended for personal development and is not signed
with a Developer ID or notarized. Apps exported from a local build may require
right-clicking the app and choosing **Open** on first launch.
