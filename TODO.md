# TODO

## 1. Menu bar cleanup

- [ ] Remove the "Restart Echo" button from the menu.
- [ ] Move Language out of the Settings submenu and into the main menu.
- [ ] Add a Help window.
- [ ] Add keyboard shortcuts to Copy Last Transcript and Paste Last Transcript Again.
- [ ] Strip the Debug window out of exported/release builds.
- [ ] Remove the "Hold Fn to dictate" hint text from the menu.
- [ ] Open question: is the "N words dictated" stat worth keeping, or should it go?
- [ ] Move the "Last: X.Xs" latency readout onto the "N today · M words dictated" line.

## 2. More styles

- [ ] Add a couple more `TranscriptionStyle` cases beyond Professional/Casual (e.g. Concise, Note-taking). Keep to case/tone exemplars the prompt bias can actually deliver — bullet points/email formatting need a second LLM pass per status.md, not a style exemplar.

## 3. Code cleanup

- [ ] Remove (or wire up) `DictationController.menuBarSymbol` — currently unused, left over from the earlier phase-swapping icon (status.md).

## 4. Future, not now

- [ ] Bring-your-own-key settings UI: replace the hardcoded/env-var Groq key (`AppSettings.resolvedAPIKey`) with a settings UI where users paste their own key, stored in Keychain.
- [ ] Filler-word removal (um/uh/like) as a style post-process — cheap via a regex sweep, called out as the next easy win in status.md but not yet built.
