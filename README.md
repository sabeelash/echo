<p align="center">
  <img src="docs/echo-logo.svg" width="460" alt="Echo logo and wordmark">
</p>

# Echo

Echo is a fast, native macOS dictation app. Hold the Fn key, speak, and release
to paste the transcript into the field you were using.

It runs quietly in the menu bar and supports both on-device transcription and
Groq's cloud-hosted Whisper models.

## Highlights

- Hold-to-talk dictation with the Fn key
- On-device transcription through Apple's Speech framework
- Groq Whisper transcription with automatic connection pre-warming
- Automatic Groq fallback when on-device transcription fails
- Professional and casual output styles
- Custom vocabulary for names, jargon, and acronyms
- Direct Accessibility paste with a clipboard fallback for browsers and
  Electron apps
- Microphone selection, language hints, usage statistics, and launch at login
- Groq API keys stored in macOS Keychain

## Requirements

- macOS 26.5 or later
- Xcode 26.6 or later to build from source
- Microphone permission
- Accessibility permission for global Fn-key monitoring and reliable pasting
- A Groq API key when using the Groq engine or cloud fallback

## Build and run

1. Open `echo.xcodeproj` in Xcode.
2. Select the `echo` scheme and the **My Mac** destination.
3. Press **⌘R**.
4. Grant Microphone and Accessibility access when prompted.
5. If macOS assigns another action to Fn, open **System Settings → Keyboard**
   and set **Press 🌐 key to** to **Do Nothing**.

You can also build from the command line:

```bash
xcodebuild \
  -project echo.xcodeproj \
  -scheme echo \
  -configuration Debug \
  build
```

## Set up transcription

When you select the Groq engine, Echo asks for an API key if none is saved. The
key is stored in macOS Keychain and can be changed from
**Settings → Groq API Key…**.

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

## Privacy

- On-device transcription stays on the Mac when it succeeds.
- Audio is sent to Groq when the Groq engine is selected or when cloud fallback
  is needed.
- The Groq API key is stored in macOS Keychain, not in the project or
  `UserDefaults`.
- Echo does not include analytics or telemetry.

## Project structure

| Path | Purpose |
| --- | --- |
| `echo/echoApp.swift` | App entry point and menu-bar scenes |
| `echo/DictationController.swift` | Hold-to-talk transcription pipeline |
| `echo/AudioRecorder.swift` | Microphone capture and M4A encoding |
| `echo/LocalTranscriber.swift` | On-device streaming transcription |
| `echo/GroqClient.swift` | Groq transcription client |
| `echo/Paster.swift` | Accessibility and clipboard paste paths |
| `echo/AppSettings.swift` | Persisted app configuration |
| `echo/APIKeyStore.swift` | Keychain-backed Groq credential storage |

## Distribution

The project is currently intended for personal development and is not signed
with a Developer ID or notarized. Apps exported from a local build may require
right-clicking the app and choosing **Open** on first launch.
