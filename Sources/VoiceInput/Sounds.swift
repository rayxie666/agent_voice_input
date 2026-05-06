import AppKit

/// Short feedback chimes played when recording starts and stops. We use the
/// macOS built-in system sounds (no resource bundling) so the app stays small
/// and the cues match the platform's vocabulary.
enum FeedbackSounds {
    /// "Tink" — short, high — reads as "I'm listening".
    static func playStart() {
        NSSound(named: NSSound.Name("Tink"))?.play()
    }

    /// "Pop" — short, lower-pitched — reads as "got it / closed".
    static func playStop() {
        NSSound(named: NSSound.Name("Pop"))?.play()
    }
}
