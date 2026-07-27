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

    /// Smallest path that triggers the microphone permission request.
    /// If the user has already decided, the system does not prompt again and
    /// the completion fires immediately with the existing answer.
    static func requestMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        log.info("Requesting microphone access (current status: \(string(for: status), privacy: .public))")

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            log.info("Microphone access \(granted ? "GRANTED" : "DENIED", privacy: .public)")
        }
    }

    // MARK: - Accessibility

    /// Checks accessibility trust and asks macOS to show the "open System
    /// Settings" dialog if the app is not yet trusted.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        log.info("Accessibility trusted: \(trusted ? "YES" : "NO", privacy: .public) (prompted)")
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
