//
//  Permissions.swift
//  echo
//
//  Smallest code paths for the two permissions echo needs:
//    1. Microphone   — required to capture audio with AVAudioEngine
//    2. Accessibility — required to paste via the AX API into the focused field
//
//  Everything here logs to the unified system log (visible in Console.app and
//  the Xcode console) under the "sabeel.echo" subsystem, category "permissions".
//

import AVFoundation
import ApplicationServices
import os

enum Permissions {
    private static let log = Logger(subsystem: "sabeel.echo", category: "permissions")

    // MARK: - Microphone

    /// Current mic authorization without prompting.
    static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// Smallest path that triggers the microphone permission request.
    /// If the user has already decided, the system does not prompt again and
    /// the completion fires immediately with the existing answer.
    static func requestMicrophone() {
        let status = microphoneStatus
        log.info("Requesting microphone access (current status: \(string(for: status), privacy: .public))")

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            log.info("Microphone access \(granted ? "GRANTED" : "DENIED", privacy: .public)")
        }
    }

    // MARK: - Accessibility

    /// Whether this process is trusted for the Accessibility API. Does not prompt.
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Checks accessibility trust and, when `prompt` is true, asks macOS to show
    /// the "open System Settings" dialog if the app is not yet trusted.
    @discardableResult
    static func checkAccessibility(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        log.info("Accessibility trusted: \(trusted ? "YES" : "NO", privacy: .public)\(prompt ? " (prompted)" : "", privacy: .public)")
        return trusted
    }

    // MARK: - Launch-time status report

    /// Logs the current state of both permissions. Called on every app launch.
    static func logStatusOnLaunch() {
        let mic = microphoneStatus
        let ax = isAccessibilityTrusted
        log.info("=== echo permission status ===")
        log.info("Microphone:    \(string(for: mic), privacy: .public)")
        log.info("Accessibility: \(ax ? "trusted" : "not trusted", privacy: .public)")
        log.info("==============================")
    }

    // MARK: - Helpers

    private static func string(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:    return "authorized"
        case .denied:        return "denied"
        case .restricted:    return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default:    return "unknown(\(status.rawValue))"
        }
    }
}
