# status

## Permissions

- `echo/Permissions.swift` — logs to unified log (subsystem `sabeel.echo`, category `permissions`)
  - `requestMicrophone()` — smallest path to trigger mic prompt (`AVCaptureDevice.requestAccess`)
  - `checkAccessibility(prompt:)` — `AXIsProcessTrustedWithOptions`; `isAccessibilityTrusted` for silent check
  - `logStatusOnLaunch()` — logs mic + accessibility state, no prompt
- Runs on launch (`echoApp.swift` → `applicationDidFinishLaunching`): log status, request mic, check accessibility
- Menu bar dropdown has a **Request Permissions** button that re-runs all three

## Entitlements

- App Sandbox **removed** — required so the AX paste path can control other apps
  - `ENABLE_APP_SANDBOX = NO` (Debug + Release), `echo.entitlements` emptied
  - Tradeoff: no Mac App Store; ship via Developer ID + notarization
- Built app entitlements: `get-task-allow` (debug), `files.user-selected.read-only`

## Permission strings

- `NSMicrophoneUsageDescription` (Info.plist build setting): "echo uses the microphone to record your voice for transcription."
- Accessibility has no consent popup — user adds the app manually in System Settings → Privacy & Security → Accessibility

## Dictation pipeline

Built in three isolated stages (each verified before the next).

### Stage 1 — record → transcribe round-trip
- `echo/AudioRecorder.swift` — `AVAudioEngine` taps the mic, writes straight to **M4A (AAC)** in the temp dir. `start(inputDeviceUID:)` / `stop() -> URL`. Routes the input node to the chosen device (see Settings → Microphone) **before** reading the format, since sample rate/channels depend on the active device; falls back to system default if `uid` is nil or unplugged.
- `echo/GroqClient.swift` — multipart upload to `https://api.groq.com/openai/v1/audio/transcriptions`. `transcribe(fileURL:key:model:language:)` takes key/model/language as params (no longer hardcoded); callers pass them from `AppSettings`. A non-empty `language` is sent as a hint (skips auto-detect); empty string = auto. Throws descriptive `GroqError` (missing key / HTTP code+body / decode failure).
- `echo/DebugView.swift` — **temporary** debug `Window(id: "debug")` with a Record/Stop button driving the round-trip; prints transcript to console + shows it. Kept as a known-good fallback. Opened via menu bar **Open Debug…**. Delete once stage 2/3 are trusted.

### Stage 2 — Fn hotkey + recording indicator
- `echo/FnHotkeyMonitor.swift` — detects Fn (Globe) hold/release via `NSEvent` `.flagsChanged` watching the `.function` flag (Fn is **not** a registerable hotkey, so KeyboardShortcuts/Carbon can't bind it; this is not a Carbon tap). Global + local monitors → clean `onPress`/`onRelease` edges (hold-to-talk). Needs Accessibility for the global monitor.
- `echo/RecordingOverlay.swift` — borderless non-activating `NSPanel` + `NSHostingView`, floats bottom-center over all Spaces, ignores mouse. Pulsing red dot "Recording" → spinner "Transcribing".
- `echo/DictationController.swift` (`@MainActor @Observable`) — owns recorder/groq/hotkey/overlay; `phase` enum drives the overlay. Hold Fn → record + show overlay; release → stop, transcribe, paste, hide. Instantiated and `start()`ed in `AppDelegate`.
- **OS gotcha:** set System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing**, or macOS hijacks Fn for emoji/Dictation.

### Stage 3 — hybrid paste into focused field
- `echo/Paster.swift` — `Paster.paste(_:)`:
  1. **AX first** — system-wide focused element, set `kAXSelectedTextAttribute` (inserts at caret, **no clipboard clobber**); only when the attribute is settable.
  2. **Clipboard fallback** — snapshot pasteboard (all items/types) → write text → synth ⌘V (`CGEvent`, keycode `0x09` + `.maskCommand`, `.cghidEventTap`) → wait **150ms** → restore. Covers Electron/web/terminals.
- Rationale: AX is **not** meaningfully faster than clipboard — its real win is not destroying the user's clipboard. Paste latency is negligible vs upload+inference, so optimize paste for reliability, not speed.
- Tunable: the 150ms restore delay is racy — too short → pastes old clipboard; too long → feels laggy.

## Settings (`echo/AppSettings.swift`)

No settings *window* — a Settings scene + pane existed briefly but was removed (overkill for a personal app). All config lives in the menu bar instead.

- `AppSettings.shared` (`@MainActor @Observable`) — single source of truth. Persists to `UserDefaults`; the menu bar binds to it.
  - `model: GroqModel` — `whisper-large-v3-turbo` (default) vs `whisper-large-v3`.
  - `languageCode: String` — ISO-639-1 hint (default `en`); `""` = auto-detect.
  - `inputDeviceUID: String?` — chosen mic by Core Audio **UID** (stable across reconnects, unlike the numeric device ID); nil = system default.
  - `lastTranscript: String` — most recent successful transcript, runtime-only (**not** persisted), powers **Copy Last Transcript**.
  - `resolvedAPIKey: String?` — reads `GROQ_KEY` env var (Xcode scheme → **only present under ⌘R, not an `open`ed .app**). No key entry UI yet; this is the only source.
- `echo/AudioDevices.swift` — Core Audio enumeration of input devices (id/uid/name); filters to devices with ≥1 input channel. `deviceID(forUID:)` resolves a stored UID back to a current device at record time.

## Menu bar (`echo/ContentView.swift` → `MenuBarView`)
- Model · Language · Microphone (pickers → submenus, bound to `AppSettings`) · — · Copy Last Transcript (→ pasteboard; disabled when empty) · — · Request Permissions · Open Debug… · — · Restart echo (relaunch via `open`, then terminate) · Quit
- `MicrophonePicker` is its own view so it re-reads the device list from Core Audio (`onAppear`) each time the menu opens.

## Useful commands

```bash
# Stream logs
log stream --predicate 'subsystem == "sabeel.echo"' --info

# Reset prompts to test again
tccutil reset Microphone sabeel.echo
tccutil reset Accessibility sabeel.echo

# Restart built app
killall echo 2>/dev/null; sleep 1; open ~/Library/Developer/Xcode/DerivedData/echo-*/Build/Products/Debug/echo.app
```
