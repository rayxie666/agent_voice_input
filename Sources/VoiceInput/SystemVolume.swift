import Foundation

/// Lower the system output volume while the user is dictating, so background
/// music / videos don't drown out their voice (or distract them). On stop we
/// restore the saved volume. NSAppleScript is the simplest no-permission path
/// for `set volume output volume N` — it's a Standard Additions command, not
/// cross-app scripting, so TCC doesn't prompt.
@MainActor
final class SystemVolumeDucker {
    /// The volume we saved when ducking started — nil means we're not currently ducking.
    private var savedVolume: Int?

    /// Drop the system output volume to `fraction × current`, e.g. 0.25 for "quarter as loud".
    /// No-op if we're already ducking (re-entrant safe).
    func duck(toFraction fraction: Double) {
        guard savedVolume == nil else { return }
        let current = Self.currentOutputVolume()
        savedVolume = current
        let target = max(0, min(100, Int((Double(current) * fraction).rounded())))
        // Don't bother if the user is already very quiet.
        if target < current {
            Self.setOutputVolume(target)
        }
    }

    /// Bring the volume back to wherever it was when we ducked.
    func restore() {
        guard let saved = savedVolume else { return }
        Self.setOutputVolume(saved)
        savedVolume = nil
    }

    // MARK: - AppleScript bridge

    private static func currentOutputVolume() -> Int {
        let result = runAppleScript("output volume of (get volume settings)")
        return Int(result?.int32Value ?? 50)
    }

    private static func setOutputVolume(_ percent: Int) {
        _ = runAppleScript("set volume output volume \(percent)")
    }

    private static func runAppleScript(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error = error {
            NSLog("VoiceInput: AppleScript failed: \(error)")
            return nil
        }
        return result
    }
}
