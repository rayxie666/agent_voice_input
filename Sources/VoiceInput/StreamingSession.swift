import Foundation

/// Drives incremental transcription while the user is still speaking.
///
/// Each `step` call:
///   1. Looks at the suffix of the audio buffer that hasn't been emitted yet.
///   2. Re-runs whisper on that suffix.
///   3. Walks the resulting segments in order and commits any that ended more
///      than `lagSeconds` ago — those are unlikely to be revised by future
///      audio, so we can safely type them out.
///   4. Stops at the first non-stable segment; everything after waits.
///
/// `finalize` is called after the user stops recording: it transcribes the
/// remaining tail (no stability lag, since no more audio is coming) and
/// returns whatever's left to type.
@MainActor
final class StreamingSession {
    /// Sample-index into `allSamples` up to which we've already emitted text.
    /// Everything before this point will not be re-transcribed.
    private var emittedSamples: Int = 0

    /// Guard so two whisper passes don't run concurrently for the same session.
    private var inFlight: Bool = false

    /// 16kHz mono — same as AudioRecorder's target format.
    private let sampleRate = 16_000
    /// whisper.cpp emits timestamps in centiseconds (10ms units).
    private let samplesPerCs: Int

    init() {
        self.samplesPerCs = sampleRate / 100  // 160
    }

    func reset() {
        emittedSamples = 0
        inFlight = false
    }

    /// Run one streaming pass. Returns text to inject, or nil if there's
    /// nothing newly stable yet (or if a previous pass is still running).
    func step(allSamples: [Float], whisper: WhisperEngine,
              language: String, lagSeconds: Double) async -> String?
    {
        guard !inFlight else { return nil }
        guard emittedSamples <= allSamples.count else { return nil }

        let suffix = Array(allSamples[emittedSamples..<allSamples.count])
        // Need at least 0.5s of unprocessed audio before whisper can produce
        // anything useful, and at least the lag window beyond that — there's
        // nothing to commit if the entire suffix is still in the "wait" zone.
        let minSamples = sampleRate / 2 + Int(lagSeconds * Double(sampleRate))
        guard suffix.count >= minSamples else { return nil }

        inFlight = true
        defer { inFlight = false }

        let segments: [WhisperSegment]
        do {
            segments = try await whisper.transcribeSegments(
                samples: suffix, language: language)
        } catch {
            return nil
        }

        let lagSamples = Int(lagSeconds * Double(sampleRate))
        let stabilityCutoffSamples = suffix.count - lagSamples
        guard stabilityCutoffSamples > 0 else { return nil }

        var committedText = ""
        var newEmitted = emittedSamples
        for seg in segments {
            // Segment timestamps are relative to `suffix` start.
            let segEndSamples = Int(seg.t1Cs) * samplesPerCs
            if segEndSamples <= stabilityCutoffSamples {
                committedText += seg.text
                newEmitted = emittedSamples + segEndSamples
            } else {
                break  // first unstable segment — bail; everything after waits.
            }
        }
        emittedSamples = newEmitted
        return committedText.isEmpty ? nil : committedText
    }

    /// User stopped recording: commit everything that's left, no lag check.
    func finalize(allSamples: [Float], whisper: WhisperEngine,
                  language: String) async -> String
    {
        guard emittedSamples <= allSamples.count else { return "" }
        let suffix = Array(allSamples[emittedSamples..<allSamples.count])
        guard suffix.count >= sampleRate / 4 else { return "" }  // <0.25s of tail = noise

        do {
            let segments = try await whisper.transcribeSegments(
                samples: suffix, language: language)
            emittedSamples = allSamples.count
            return segments.map(\.text).joined()
        } catch {
            return ""
        }
    }
}
