# TODO

## 1. Fail loudly, not silently

When transcription fails, `DictationController` logs the error and just hides the overlay — the user spoke for 30 seconds and gets nothing, with no indication why.

- [x] Add a brief error state to the overlay (icon flashes red, or a short "Failed — copied nothing" flash) before dismissing.

## 2. Escape-to-cancel while recording

No way to abort right now — releasing Fn always uploads/transcribes.

- [x] Pressing Esc mid-hold discards the recording (small addition to `FnHotkeyMonitor`).
- [x] Discard recordings under ~300ms so an accidental Fn tap doesn't burn a round-trip and paste garbage.

## 3. Polish items

- [x] Launch at login via `SMAppService.mainApp` — a few lines plus a menu toggle.
- [x] Clipboard restore race: fixed via a lazy `NSPasteboardItemDataProvider` — its callback fires when the app actually reads the string in response to ⌘V (reads don't bump `changeCount`, so polling that can't detect consumption); `changeCount` is still checked before restoring so a concurrent write is never clobbered. 1s timeout fallback.
- [x] `transcriptionsToday` only rolls over on the next dictation, so it can show yesterday's count — check the date when the menu opens instead.
- [x] Paste last transcript again — a menu item / shortcut to re-paste `lastTranscript` without re-recording.
- [x] Show current settings (engine, model, style) in the menu bar status area, same treatment as the phase header (Idle / "Hold Fn to dictate") — so the active config is visible at a glance without opening the Settings submenu.
