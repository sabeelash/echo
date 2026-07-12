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
- `echo/GroqClient.swift` — multipart upload to `https://api.groq.com/openai/v1/audio/transcriptions`. `transcribe(fileURL:key:model:language:prompt:)` takes key/model/language/prompt as params (no longer hardcoded); callers pass them from `AppSettings`. A non-empty `language` is sent as a hint (skips auto-detect); empty string = auto. A non-empty `prompt` is sent as the Groq `prompt` field (vocabulary + style steering — see **Transcription prompt** below); empty = omitted. Throws descriptive `GroqError` (missing key / HTTP code+body / decode failure).
  - **Groq `/audio/transcriptions` params** (reference): `file`/`url` (one required), `model` (required: `whisper-large-v3` / `whisper-large-v3-turbo`), `language` (ISO-639-1), `prompt` (≤224 tokens, style/spelling bias — **not** instruction-following), `response_format` (`json`/`verbose_json`/`text`, echo uses `json`), `temperature` (0–1, echo leaves at default 0), `timestamp_granularities[]` (needs `verbose_json`, unused). Files ≤25MB free / 100MB dev tier; downsampled to 16kHz mono server-side. Only `prompt` was worth wiring up — the rest are defaults or irrelevant to a paste-the-string flow.
- `echo/DebugView.swift` — **temporary** debug `Window(id: "debug")` with a Record/Stop button driving the round-trip; prints transcript to console + shows it. Kept as a known-good fallback. Opened via menu bar **Open Debug…**. Delete once stage 2/3 are trusted.

### Stage 2 — Fn hotkey + recording indicator
- `echo/FnHotkeyMonitor.swift` — detects Fn (Globe) hold/release via `NSEvent` `.flagsChanged` watching the `.function` flag (Fn is **not** a registerable hotkey, so KeyboardShortcuts/Carbon can't bind it; this is not a Carbon tap). Global + local monitors → clean `onPress`/`onRelease` edges (hold-to-talk). Needs Accessibility for the global monitor.
- `echo/RecordingOverlay.swift` — borderless non-activating `NSPanel` + `NSHostingView`, floats bottom-center over all Spaces, ignores mouse. `PulsingIcon` component renders `Image("MenuBarIcon")` as a template: red at 0.6s period (recording) → white at 0.3s period (transcribing). No text labels.
- `echo/DictationController.swift` (`@MainActor @Observable`) — owns recorder/groq/hotkey/overlay; `phase` enum drives the overlay. Hold Fn → record + show overlay; release → stop, transcribe, paste, hide. `DictationController.shared` singleton (so the menu/icon observe the same `phase`); `start()`ed in `AppDelegate`.
- **OS gotcha:** set System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing**, or macOS hijacks Fn for emoji/Dictation.

### Stage 3 — hybrid paste into focused field
- `echo/Paster.swift` — `Paster.paste(_:)`:
  1. **AX first** — system-wide focused element, set `kAXSelectedTextAttribute` (inserts at caret, **no clipboard clobber**); only when the attribute is settable **and the write is verified** (see below).
  2. **Clipboard fallback** — snapshot pasteboard (all items/types) → write text → synth ⌘V (`CGEvent`, keycode `0x09` + `.maskCommand`, `.cghidEventTap`) → wait **150ms** → restore. Covers Electron/web/terminals.
- **Browser paste bug + fix (must verify the AX write):** Chrome and WebKit web views report `kAXSelectedTextAttribute` as *settable* and `AXUIElementSetAttributeValue` returns `.success`, but the write is **silently dropped** — nothing lands in the field. The old code trusted the return code, declared success, and never reached the clipboard fallback → **nothing pasted in the browser**. Fix: snapshot `kAXNumberOfCharactersAttribute` before/after the set and require it grew (`after > before`); otherwise return `false` so the clipboard `⌘V` path runs. Use the *char count* (an `Int`), not full `kAXValueAttribute`, so verification doesn't copy an entire large document's text on every paste.
  - Edge case: a native control that honors the AX write but doesn't expose a char count routes through clipboard instead (correct, slightly slower). All standard AppKit text controls expose the count, so this is rare. Reading back the value text would close it but pays the expensive copy we're avoiding.
- Rationale: AX is **not** meaningfully faster than clipboard — its real win is not destroying the user's clipboard. Paste latency is negligible vs upload+inference, so optimize paste for reliability, not speed.
- Tunable: the 150ms restore delay is racy — too short → pastes old clipboard; too long → feels laggy.

## Transcription prompt (vocabulary + style)

echo sends Groq a `prompt` to steer output. Key fact: **Whisper's prompt is conditioning text treated as if it were the transcript immediately preceding the audio — it mimics the prompt's *style*, it does not follow instructions.** Writing "remove profanity" or "format as bullets" does nothing (and can leak into output). It's a *soft bias*, never a guarantee; Groq looks at roughly the last 224 tokens.

`AppSettings.groqPrompt` assembles what gets sent: the user's **vocabulary** terms followed by the selected **style** exemplar, space-joined (vocab dropped if empty).

- **Custom Vocabulary** (`vocabularyPrompt: String`, persisted) — free-text names/jargon/acronyms echo should spell correctly (e.g. `echo, Groq, SwiftUI, Sabeel, kAXSelectedTextAttribute`). Edited in `echo/VocabularyView.swift` — a 400×300 `Window(id: "vocabulary")` styled like the Debug panel (red template `MenuBarIcon` at top, title, caption, `TextEditor` with placeholder + 224-token note). Opened via menu **Settings → Custom Vocabulary…**. Edits write straight through to `AppSettings` (no Save button).
  - Placeholder alignment gotcha: the `TextEditor` has `.padding(8)` and ~5pt internal line-fragment padding, so the placeholder overlay pads `13` horizontal / `8` vertical to sit on the first text row. If insets drift on another display, switch to a `ZStack` sharing the same text container.
- **Style** (`style: TranscriptionStyle`, persisted, default `.professional`) — menu picker under Model. Two cases, each with an `exemplar` written *in* its own style (since Whisper mimics):
  - `.professional` — proper-case, punctuated exemplar → clean sentences. Leaves Groq output untouched in post.
  - `.casual` — all-lowercase exemplar → relaxed output. **Plus deterministic post-processing**: `postProcess(_:)` force-lowercases the whole transcript (`text.lowercased()`) because the prompt bias alone can't stop Whisper capitalizing "I" / proper nouns / sentence starts. Trade-off: also lowercases vocab terms (`SwiftUI` → `swiftui`), consistent with "no capitalization at all."
  - Applied in `DictationController` (real dictation) and `DebugView` (round-trip) right after `transcribe` returns, before paste/record, via `style.postProcess(raw)`.

**What the prompt can / can't do (for future styles):**
- *Cheap & reliable (prompt bias ± regex/post-process):* casual/professional casing (done), filler-word removal (`um`/`uh`/`like` — best with a regex sweep, not just bias), numbers-as-digits, strip-trailing-period.
- *Not possible via prompt — needs a second LLM pass:* bullet points, email formatting, grammar rephrase, summarize, translate. These mean transcribe → Groq `llama-*` cleanup → paste, adding a ~200–500ms round-trip that cuts against echo's "fastest" goal. Gate behind an explicit style if ever added; **not** a default. Next easy win considered: **filler-word removal** (not yet built).

## Speed optimizations (latency)

Both live in the `beginRecording` → release → paste cycle and target the overhead *around* Groq inference (which dominates total latency). Neither sits on the critical release→paste path, so neither adds latency.

- **Pre-warm the Groq connection** — `GroqClient.prewarm()` fires a fire-and-forget `HEAD` on `URLSession.shared` to the transcriptions endpoint. The response is irrelevant (it 405s); the point is the TLS/TCP connection it opens lands in the shared session's pool, so the real `POST` on release reuses a warm socket instead of paying a ~2–3 RTT handshake. Called from `DictationController.beginRecording()`, so it warms *while the user is still speaking*. `resume()` is non-blocking, so it doesn't delay record start.
  - Win is biggest on the **first dictation after idle**; back-to-back dictations already reuse a live socket (URLSession keep-alive), so the readout won't change there. To observe: dictate, wait ~60s+, compare cold-vs-warm `Last: X.Xs`.
  - No regression risk: Groq serves **HTTP/2** (multiplexed, no head-of-line blocking between a lingering HEAD and the POST); worst case URLSession opens a second connection (warm-up wasted, not slower).
- **Critical process activity** — `DictationController.beginActivity()` / `endActivity()` wrap `ProcessInfo.beginActivity(options: [.userInitiated, .latencyCritical])`. echo is a menu-bar app with no focused window → prime App Nap target; this stops macOS throttling the audio engine / network mid-dictation. Held for the whole hold→transcribe→paste cycle; `endActivity()` is called on **every** exit path (record-start failure, stop-returns-nil, no API key, transcribe failure, post-paste) so the token never leaks.
  - This is **jitter/tail-latency insurance**, not a consistent X ms saved — it removes occasional throttled bad runs, won't show as a number on good runs.

### Evaluated and dropped — time-stretch & VAD trim
Both were listed as "planned" in CLAUDE.md, evaluated, and **rejected**. They predate knowing how fast Groq turbo is: `whisper-large-v3-turbo` runs at **~200× real-time**, so inference is already ~50ms for a 10s clip (~300ms for 60s) and is **not** the bottleneck — network RTT + Groq's fixed per-request overhead is. Both features attack the duration-dependent slice (inference) while adding cost on the critical release→paste path.

- **Time-stretch 1.5×** (`AVAudioUnitTimePitch` offline render → re-encode): saves ~17ms on a 10s clip (~100ms at 60s) but adds ~100–300ms of offline render + AAC re-encode after release. **Net loss** for typical clips, ~wash even for long ones.
- **VAD trim**: hold-to-talk already has minimal leading/trailing silence, so trimming saves ~2ms. Worse, the current recorder encodes AAC **during** recording inside the tap (overlapped, effectively free); any trim approach needs raw PCM and re-encodes **at stop**, moving the full ~30–80ms encode **onto** the critical path. **Net loss.**
- Conclusion: don't re-add these. The remaining latency is **network RTT + request overhead** — addressed by pre-warm above. The only duration-style idea that attacks the *dominant* (network) slice is **streaming/chunked upload during recording** (upload mostly done by release); not yet implemented.

## Local transcription prototype (SpeechTranscriber vs Groq)

Prototype for replacing/augmenting Groq with the on-device **SpeechAnalyzer / SpeechTranscriber** API (macOS 26 Speech framework). Motivation: the remaining Groq latency is network RTT + fixed request overhead (~1s), which no client-side work can remove; on-device streaming transcription removes the network entirely. Chosen over WhisperKit/whisper.cpp because the model asset is **system-managed** (`AssetInventory`) and inference runs **out of process** — zero cost to echo's ~32MB footprint, which matters on 8GB machines.

- `echo/LocalTranscriber.swift` — one streaming session: `startSession(languageCode:)` (maps ISO code via `supportedLocale(equivalentTo:)`, downloads model on first use, `prepareToAnalyze` preheats), `feed(_:)` (called on the audio tap thread; converts hardware format → analyzer's preferred `16kHz mono Int16` via `AVAudioConverter`, yields `AnalyzerInput` into an `AsyncStream`), `finish()` (ends input, `finalizeAndFinishThroughEndOfInput`, returns transcript). Reporting options `[.volatileResults, .fastResults]` → live partial text via `onPartial` while the user is still speaking. `modelRetention: .processLifetime` keeps the model warm across dictations.
- `AudioRecorder.onBuffer` — optional side-channel handing raw tap buffers to the prototype alongside the file write; production Groq path untouched.
- `echo/DebugView.swift` — head-to-head harness: one recording feeds both engines (file → Groq at stop; tap buffers → local *during* recording), both latencies measured from the same stop instant, shown side by side. Local pane updates live while speaking.
- **Measured on the M1/8GB (CLI harness, 8.6s synthesized clip):** model already installed system-wide, `prepareToAnalyze` ~0.2s, **finalize latency 0.35s** after end of input (streaming path) / 0.25s (file convenience path), transcript verbatim-correct including "M1". Live dictation should be ≤ this, since audio streams in real time and only the tail needs finalizing at Fn-release. Groq round-trips are typically ~1s+ → local wins on latency; accuracy/vocab comparison needs real dictations via the Debug window.
- Gotchas: `AVAudioFile.read(into:)` throws a bare `nilError` at exact EOF (bit the harness; live tap path unaffected). Volatile results can glitch mid-word ("speecheech") but finals are clean.
- Style exemplars don't apply locally (only `postProcess` runs — casual lowercasing works, professional is a no-op anyway).

### Local vocabulary (module choice)

The local analogue of the Groq `prompt` is `AnalysisContext.contextualStrings` — but **SpeechTranscriber ignores it** (known framework limitation; both `setContext` and the `analysisContext:` init were tested, zero effect). **DictationTranscriber honors it**, so `LocalTranscriber.startSession(languageCode:vocabulary:)` picks the module:

- **Vocabulary empty → SpeechTranscriber** (`[.volatileResults, .fastResults]`) — better baseline accuracy + punctuation.
- **Vocabulary set → DictationTranscriber** (`contentHints: [.shortForm]`, `transcriptionOptions: [.punctuation]`, `reportingOptions: [.volatileResults, .frequentFinalization]`) with `contextualStrings = [.general: terms]` attached via the `SpeechAnalyzer(inputSequence:…analysisContext:)` init.
- A/B on the M1 (synthesized "I asked Sabeel to prewarm the Groq client before the WhisperKit comparison"): SpeechTranscriber ± vocab → "Sabiel / Grock / Whisper Kit" (vocab ignored); DictationTranscriber without vocab → "Samuel / grout client / whisper kit"; **DictationTranscriber with vocab → every term exact**, finalize 0.18s. Trade-off: DictationTranscriber's punctuation is lighter (dropped the trailing period), baseline slightly weaker — acceptable since it only runs when vocab is set, which is when the terms matter.
- `AppSettings.vocabularyTerms` splits `vocabularyPrompt` on commas/newlines only (multi-word names survive); both `DictationController` and `DebugView` pass it. Vocabulary panel copy updated (comma-separated, hints both engines).

### Engine switch (wired into real dictation)

`AppSettings.engine` (`TranscriptionEngine`: `.groq` default / `.local`, persisted) selects the dictation engine; top-level **Engine** picker in the menu bar (the Groq **Model** picker only shows when the engine is Groq).

- **Fn-down** (`DictationController.beginRecording`): Groq → `prewarm()` as before; local → `recorder.onBuffer` streams tap buffers to `LocalTranscriber` and `startSession` runs concurrently in `localSession: Task`. Recording starts immediately either way — `LocalTranscriber.feed` holds early buffers under a lock (cap ~25s) and flushes them when the session comes up (~0.2–0.4s warm), so the first words aren't lost.
- **Fn-up** (`endRecording`): local path awaits the session task then `local.finish()` (audio already streamed; just finalization), **capped at 10s** (`localFinishTimeout`, raced via a first-wins continuation — a task group can't race a hung `Task.value` since it ignores cancellation). **Any local failure or timeout falls back to Groq with the recorded m4a** — same audio, slower path, no lost speech; needs the API key only on that fallback. Without the cap, a hang (e.g. first-use model download) would wedge `phase` at `.transcribing` and kill dictation until relaunch. Empty transcripts are dropped (no paste, no stats bump).
- The m4a is always recorded even on the local path — it's the fallback payload; deleted after transcription as before.
- Abandoned sessions (record-start failure, stop-returns-nil) are cleaned up by awaiting session startup then `cancel()`, so the cancel can't race `startSession`.

## Settings (`echo/AppSettings.swift`)

No settings *window* — a Settings scene + pane existed briefly but was removed (overkill for a personal app). All config lives in the menu bar instead.

- `AppSettings.shared` (`@MainActor @Observable`) — single source of truth. Persists to `UserDefaults`; the menu bar binds to it.
  - `engine: TranscriptionEngine` — `.groq` (default) vs `.local` (on-device SpeechTranscriber; see **Engine switch**). **Persisted.**
  - `model: GroqModel` — `whisper-large-v3-turbo` (default) vs `whisper-large-v3`.
  - `languageCode: String` — ISO-639-1 hint (default `en`); `""` = auto-detect.
  - `inputDeviceUID: String?` — chosen mic by Core Audio **UID** (stable across reconnects, unlike the numeric device ID); nil = system default.
  - `vocabularyPrompt: String` / `style: TranscriptionStyle` — **persisted**; feed the Groq `prompt`. `groqPrompt` combines them (see **Transcription prompt** above). `TranscriptionStyle` (`.professional` default / `.casual`) carries an `exemplar` (appended to the prompt) and `postProcess(_:)` (casual force-lowercases).
  - `lastTranscript: String` — most recent successful transcript, runtime-only (**not** persisted), powers **Copy Last Transcript**.
  - `lastLatency: TimeInterval?` — round-trip seconds of the last transcription (the `dt` measured in `DictationController`), runtime-only; powers the menu's **Last: 1.2s** readout.
  - `transcriptionsToday: Int` / `totalWords: Int` — `private(set)`, **persisted**. Vanity/feedback stats shown in the menu.
  - `recordTranscription(_:latency:)` — single entry point called on every successful transcript: sets `lastTranscript` + `lastLatency`, bumps `transcriptionsToday` (resets at midnight via stored `countDate`), adds word count to `totalWords`. Replaces the old direct `lastTranscript =` assignment.
  - `resolvedAPIKey: String?` — prefers a **hardcoded** key (personal use; works in an `open`ed .app), falling back to the `GROQ_KEY` **env var** (Xcode scheme → only present under ⌘R), else nil. Placeholder `gsk_PASTE_YOUR_KEY_HERE` counts as unset, so leaving it untouched keeps the env-var path. Temporary — replace with Keychain (read-once-and-cache; see `keychain-todo.md`). **Don't commit a real key.**
- `echo/AudioDevices.swift` — Core Audio enumeration of input devices (id/uid/name); filters to devices with ≥1 input channel. `deviceID(forUID:)` resolves a stored UID back to a current device at record time.

## Menu bar (`echo/ContentView.swift` → `MenuBarView`)
- Status header (phase `Label`: Idle / Recording… / Transcribing…) · "Hold Fn to dictate" hint · — · Model · **Style** · Microphone (pickers → submenus, bound to `AppSettings`) · — · last-transcript preview (first ~40 chars, one line, shown only when non-empty) · Copy Last Transcript (→ pasteboard; disabled when empty) · — · **Last: 1.2s** · **N today · M words dictated** · — · **Settings** submenu · Quit
- **Settings** submenu (`Menu("Settings")`) groups the secondary controls: Language picker · Request Permissions · **Custom Vocabulary…** (opens `Window(id: "vocabulary")`) · Open Debug… · **Restart Echo** (relaunch via `open`, then terminate). Keeps the top level focused on per-dictation choices (Model, Style, Microphone) + stats. Top-level quit button is **Quit Echo**.
- Plain `Text` / phase `Label` rows render as the standard grayed-out (non-interactive) menu labels — used for the header, hint, preview, and stats.
- `MicrophonePicker` is its own view so it re-reads the device list from Core Audio (`onAppear`) each time the menu opens.
- The menu observes `DictationController.shared` (singleton) for live `phase`, surfaced as the in-menu **status header** (`Label`: `circle` Idle / `record.circle` Recording… / `ellipsis.circle` Transcribing…). The `MenuBarExtra` icon itself is a **static custom asset** `Image("MenuBarIcon")` (set in `echoApp.swift`) — it does **not** change with phase. `DictationController.menuBarSymbol` exists but is currently unused (left over from the earlier phase-swapping icon).
- Stats caveat: `transcriptionsToday` only rolls over to 0 on the next dictation after midnight (not on menu-open), so it can briefly show yesterday's count.

## Packaging

Personal-use distribution only (no Apple Developer paid account → no Developer ID, no notarization).

### Build settings (project.pbxproj, both Debug + Release)
- `INFOPLIST_KEY_CFBundleDisplayName = Echo` — display name shown in Finder/Dock/Spotlight
- `INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.productivity`
- `INFOPLIST_KEY_NSHumanReadableCopyright = © 2026 Sabeel`
- `MARKETING_VERSION = 1.0` / `CURRENT_PROJECT_VERSION = 1`

### App icon
- `echo/Assets.xcassets/AppIcon.appiconset/` — slots defined in `Contents.json`, **no images yet**. Need a 1024×1024 master PNG; generate sizes with `iconutil` or [icon.kitchen](https://icon.kitchen), set "Render As → Original" in Xcode.
- Menu bar icon: `echo/Assets.xcassets/MenuBarIcon` SVG image set, "Render As → Template Image", "Scales → Single Scale". Used in `echoApp.swift` (`Image("MenuBarIcon")`) and `RecordingOverlay.swift` (`PulsingIcon`).

### Distribution
- Product → Archive in Xcode → Distribute App → Copy App → export `echo.app`
- Drag to `/Applications`
- First launch on a new machine: right-click → Open to bypass Gatekeeper (no notarization)

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
