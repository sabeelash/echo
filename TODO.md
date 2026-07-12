# TODO

## 1. Get the real API key out of source (urgent)

`AppSettings.swift` (`resolvedAPIKey`) has a live Groq key hardcoded in the working tree — one careless `git add -A` away from being committed. `keychain-todo.md` already has the full plan, including the read-once-and-cache fix for the slowdown that caused problems last time. ~1 hour of work; also removes the "`GROQ_KEY` only works under ⌘R" limitation.

- [ ] Rotate the current key once it's out of the working tree (it's been sitting there).

## 2. Fail loudly, not silently

When transcription fails, `DictationController` logs the error and just hides the overlay — the user spoke for 30 seconds and gets nothing, with no indication why.

- [ ] Add a brief error state to the overlay (icon flashes red, or a short "Failed — copied nothing" flash) before dismissing.
- [ ] Don't delete the recording on failure. The `defer` in `DictationController.swift` removes the m4a on every exit path, so a network blip destroys the user's speech. Keep the last failed recording and offer a "Retry last" menu item.

## 3. Escape-to-cancel while recording

No way to abort right now — releasing Fn always uploads/transcribes.

- [ ] Pressing Esc mid-hold discards the recording (small addition to `FnHotkeyMonitor`).
- [ ] Discard recordings under ~300ms so an accidental Fn tap doesn't burn a round-trip and paste garbage.

## 4. Streaming upload during recording (speed)

The remaining Groq latency is network RTT + request overhead. Chunked upload of the multipart body while the user is still speaking (so only the tail uploads after Fn-release) is the one unimplemented idea that attacks it directly. Hardest item on this list — prototype behind a flag and measure like the other speed experiments in `status.md`.

## 5. Smaller polish items

- [ ] Launch at login via `SMAppService.mainApp` — a few lines plus a menu toggle.
- [ ] Clipboard restore race: the fixed 150ms wait in `Paster` is racy. Poll `NSPasteboard.changeCount` until the synthetic ⌘V is consumed (with a timeout) instead of always waiting 150ms.
- [ ] App icon — the `AppIcon.appiconset` slots are still empty.
- [ ] Tests: `echoTests` is still the template. Genuinely testable units: `TranscriptionStyle.postProcess`, `groqPrompt` assembly, the multipart body builder in `GroqClient` (extract it, verify boundaries/fields without hitting the network).
- [ ] `transcriptionsToday` only rolls over on the next dictation, so it can show yesterday's count — check the date when the menu opens instead.
