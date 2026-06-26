# Keychain API key storage — how to do it without the slowdown

## What went wrong last time

Moving the Groq API key from the `GROQ_KEY` env var into the Keychain made
dictation noticeably slower. The cause was **not** Keychain being inherently
slow — it was reading the key on the hot path.

`DictationController.endRecording()` reads `settings.resolvedAPIKey` on the
`@MainActor`, synchronously, on **every dictation** (right at Fn-release →
transcribe, the most latency-sensitive moment). With the env var that's a free
dictionary lookup. Backed by Keychain it becomes a synchronous
`SecItemCopyMatching` per dictation, and Keychain reads are neither cheap nor
consistent:

- First access after launch is slow while `securityd` warms up (tens of ms).
- Sandbox is removed + debug/ad-hoc signing **changes every build**, so the
  item's ACL gets re-evaluated against a new code signature → macOS re-runs
  trust checks (or prompts) on each access. This is the "got slow *quickly*"
  feeling.

## The fix: read once, cache in memory

The API key never changes mid-session, so never touch Keychain per-dictation.
Read it once (lazily on first use, or at launch) into a cached `String?`; the
hot path reads the cache.

```swift
// AppSettings.swift
@ObservationIgnored private var cachedKey: String?

var resolvedAPIKey: String? {
    if let cachedKey { return cachedKey }
    let key = Keychain.read("groq-api-key")   // the only SecItemCopyMatching
    cachedKey = key
    return key
}
```

When the user enters/updates the key, write to Keychain **and** refresh the
cache (`cachedKey = newValue`) so the next read doesn't hit Keychain again.

## Write path gotcha

The other classic Keychain slowdown is calling `SecItemAdd` on every save
without deleting/updating first — duplicate items pile up. Use delete-then-add
(or `SecItemUpdate`).

## Implementation checklist

- [ ] `echo/Keychain.swift` — `read` / `save` / `delete` for service
      `sabeel.echo`, account `groq-api-key`. Use `kSecAttrAccessibleAfterFirstUnlock`.
- [ ] `AppSettings.resolvedAPIKey` — cache in memory (see above); no per-call
      Keychain read.
- [ ] Key-entry field in the menu bar (SecureField) → `Keychain.save` +
      refresh `cachedKey`.
- [ ] Removes the current limitation: `GROQ_KEY` only works under ⌘R, not an
      `open`ed `.app`.
