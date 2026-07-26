# TODO

- [x] Remove the "Restart Echo" button from the menu.

- [x] Add a Help window.
  No Help window exists yet. Follow the pattern used by the existing "Custom Vocabulary…" and "Open Debug…" windows ([ContentView.swift:105-113](echo/ContentView.swift:105)): register a new `WindowGroup` with a unique id (e.g. `"help"`) in `echoApp.swift`, add a menu item that calls `openWindow(id: "help")`, and build a SwiftUI view for the content. Decided contents:
  - Keyboard shortcuts table: **Hold Fn** — dictate; **⌃⌘V** — paste last transcript.
  - One-liner per Style (what each does).
  - Transcription engines: explain the on-device model (SpeechAnalyzer) vs Groq, and when each is used.
  - Note that the Groq API key is currently hardcoded (until the bring-your-own-key settings UI lands — see For Later).
  - Permissions troubleshooting: mic + Accessibility (AX paste silently degrades without it).
  - Tone: modern SaaS copy — confident and friendly, no jargon, no filler.

- [x] ~~Add keyboard shortcut to "Paste Last Transcript Again"~~ — dropped. Built as an NSEvent global keyDown monitor (⌃⌘V), but it didn't fire reliably in testing and the menu item covers the use case; removed rather than debugged further.

- [x] Strip the Debug window out of exported/release builds.

- [x] Remove the "Hold Fn to dictate" hint text from the menu.

- [x] Merge the stats into one compact line: `N today · M words · X.Xs` ([ContentView.swift:86](echo/ContentView.swift:86)).
  Decided: keep the words-dictated stat (it's the value/retention number), fold the "Last: X.Xs" latency readout into the same line, drop the "dictated" suffix and the separate latency line.

- [x] Fold numerals-as-digits bias into the existing `.professional` and `.casual` exemplars (e.g. "meeting starts at 3pm, budget is $12,500, room 204" / "i'll grab 2 coffees and meet you at 5") instead of making it its own style — it's an orthogonal formatting axis, not a tone choice, so it shouldn't force users to give up casual/professional to get it.

- [x] Remove (or wire up) `DictationController.menuBarSymbol` — currently unused, left over from the earlier phase-swapping icon (status.md).

---

# For Later, DO NOT DO THESE NOW.

- [x] Bring-your-own-key settings UI: the first-run/setup panel and **Settings → Groq API Key…** both save the user's key in macOS Keychain. `AppSettings.resolvedAPIKey` reads only from Keychain; no key or environment-variable fallback is embedded in the app.

- [ ] Filler-word removal (um/uh/like) as a style post-process — cheap via a regex sweep, called out as the next easy win in status.md but not yet built.
  Per `status.md` (line 63), this belongs in the "cheap & reliable" bucket — a deterministic regex sweep over the transcript, not something achievable via the Groq prompt bias alone. Likely implemented as another branch in (or alongside) `TranscriptionStyle.postProcess(_:)` at [AppSettings.swift:104-109](echo/AppSettings.swift:104), stripping standalone `um`/`uh`/`like` tokens (word-boundary matches, case-insensitive) after the transcript comes back, before it's pasted. Open question: whether it's on-by-default, tied to a specific style, or a separate toggle — not yet decided.
