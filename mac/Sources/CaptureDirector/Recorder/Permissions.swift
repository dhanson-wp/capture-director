import ApplicationServices
import CoreGraphics

/// Screen Recording and Accessibility, which record mode needs before it touches anything.
enum Permissions {
    static let screenRecordingMissing = "Capture Director needs Screen Recording permission. Turn it on in System Settings > Privacy & Security > Screen & System Audio Recording, then record again."
    static let accessibilityMissing = "Capture Director needs Accessibility permission. Turn it on in System Settings > Privacy & Security > Accessibility, then record again."

    /// Asks macOS once for whatever is missing (so both prompts come up in one run),
    /// then returns the sentence for the first missing permission, or nil when both are on.
    static func check() -> String? {
        let screen = CGPreflightScreenCaptureAccess()
        let accessibility = AXIsProcessTrusted()
        if !screen { _ = CGRequestScreenCaptureAccess() }
        if !accessibility {
            // The key behind kAXTrustedCheckOptionPrompt, spelled out because that global isn't concurrency-safe.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        if !screen { return screenRecordingMissing }
        if !accessibility { return accessibilityMissing }
        return nil
    }
}
