<p align="center">
  <img src="docs/echo-logo.svg" width="460" alt="Echo logo and wordmark">
</p>

# Echo

Echo is a fast, native macOS dictation app. Hold the Fn key, speak, and release
to paste the transcript into the field you were using.

It runs quietly in the menu bar and supports both on-device transcription and
Groq's cloud-hosted Whisper models.

## Requirements

- macOS 26.5 or later
- Xcode 26.6 or later to build from source
- Microphone permission
- Accessibility permission for global Fn-key monitoring and reliable pasting
- A Groq API key when using the Groq engine or cloud fallback

## Set up transcription

Echo opens the Groq API key panel on first launch. The key is stored in macOS
Keychain and can be changed later from **Settings → Groq API Key…**.

Choose a transcription engine from the menu bar:

- **On-device** streams audio through Apple's Speech framework for the lowest
  latency. If local transcription fails, Echo can retry the recorded audio
  through Groq.
- **Groq** sends the recording to a selected Whisper model. Turbo favors speed;
  Large v3 favors accuracy.

## Use Echo

1. Focus any editable text field.
2. Hold **Fn** and speak.
3. Release **Fn**.
4. Echo transcribes the recording and pastes the result at the cursor.

The menu bar also provides engine, model, style, microphone, language,
vocabulary, and last-transcript controls.

## Distribution

The project is currently intended for personal development and is not signed
with a Developer ID or notarized. Apps exported from a local build may require
right-clicking the app and choosing **Open** on first launch.
