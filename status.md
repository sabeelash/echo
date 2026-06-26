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
