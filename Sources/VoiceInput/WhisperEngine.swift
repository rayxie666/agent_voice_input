import CWhisper
import Foundation

enum WhisperError: Error, LocalizedError {
    case modelNotFound(String)
    case initFailed
    case transcribeFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let p): return "Whisper model not found: \(p)"
        case .initFailed: return "whisper_init_from_file_with_params returned NULL"
        case .transcribeFailed(let c): return "whisper_full failed with code \(c)"
        }
    }
}

/// One segment of a whisper transcript, with timestamps in centiseconds
/// (10ms units, whisper.cpp's native unit).
struct WhisperSegment {
    let text: String
    let t0Cs: Int64
    let t1Cs: Int64
}

final class WhisperEngine {
    private var ctx: OpaquePointer?
    private let modelPath: String
    private let queue = DispatchQueue(label: "voiceinput.whisper", qos: .userInitiated)

    init(modelPath: String) throws {
        self.modelPath = modelPath
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw WhisperError.modelNotFound(modelPath)
        }
        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true
        guard let ctx = whisper_init_from_file_with_params(modelPath, params) else {
            throw WhisperError.initFailed
        }
        self.ctx = ctx
    }

    deinit {
        if let ctx = ctx { whisper_free(ctx) }
    }

    /// Transcribe samples (16kHz mono float32). `language` "auto" detects, or pass "zh"/"en".
    func transcribe(samples: [Float], language: String = "auto") async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [weak self] in
                guard let self = self, let ctx = self.ctx else {
                    cont.resume(throwing: WhisperError.initFailed); return
                }
                let nThreads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))

                language.withCString { langPtr in
                    var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                    params.print_realtime = false
                    params.print_progress = false
                    params.print_special = false
                    params.print_timestamps = false
                    params.translate = false
                    params.single_segment = false
                    params.no_context = true
                    params.suppress_blank = true
                    params.suppress_nst = true       // suppress non-speech tokens
                    params.temperature = 0.0         // greedy, less hallucination
                    params.temperature_inc = 0.0     // never bump temp on retry
                    params.no_speech_thold = 0.6     // skip clearly-silent segments
                    params.n_threads = nThreads
                    params.language = langPtr
                    // Note: we deliberately do NOT set `initial_prompt`. Whisper
                    // will regurgitate the prompt back as transcription when fed
                    // ambiguous/silent chunks (especially noticeable in streaming).
                    // The post-filter regex below catches subtitle-credit
                    // hallucinations instead, with no echo risk.

                    let result = samples.withUnsafeBufferPointer { buf -> Int32 in
                        whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                    }
                    if result != 0 {
                        cont.resume(throwing: WhisperError.transcribeFailed(result))
                        return
                    }
                    var text = ""
                    let nSeg = whisper_full_n_segments(ctx)
                    for i in 0..<nSeg {
                        if let cstr = whisper_full_get_segment_text(ctx, i) {
                            text += String(cString: cstr)
                        }
                    }
                    let cleaned = WhisperEngine.removeHallucinations(text)
                    cont.resume(returning: cleaned)
                }
            }
        }
    }

    /// Streaming variant: returns segments with timestamps so the caller can
    /// decide which ones are old enough to safely commit.
    func transcribeSegments(samples: [Float], language: String = "auto")
        async throws -> [WhisperSegment]
    {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [weak self] in
                guard let self = self, let ctx = self.ctx else {
                    cont.resume(throwing: WhisperError.initFailed); return
                }
                let nThreads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))

                language.withCString { langPtr in
                    var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
                    params.print_realtime = false
                    params.print_progress = false
                    params.print_special = false
                    params.print_timestamps = false
                    params.translate = false
                    params.single_segment = false
                    params.no_context = true
                    params.suppress_blank = true
                    params.suppress_nst = true
                    params.temperature = 0.0
                    params.temperature_inc = 0.0
                    params.no_speech_thold = 0.6
                    params.n_threads = nThreads
                    params.language = langPtr
                    // No initial_prompt — see comment in transcribe().

                    let result = samples.withUnsafeBufferPointer { buf -> Int32 in
                        whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                    }
                    if result != 0 {
                        cont.resume(throwing: WhisperError.transcribeFailed(result))
                        return
                    }
                    var out: [WhisperSegment] = []
                    let nSeg = whisper_full_n_segments(ctx)
                    for i in 0..<nSeg {
                        guard let cstr = whisper_full_get_segment_text(ctx, i) else { continue }
                        let raw = String(cString: cstr)
                        let cleaned = WhisperEngine.removeHallucinations(raw)
                        if cleaned.isEmpty { continue }
                        out.append(WhisperSegment(
                            text: cleaned,
                            t0Cs: whisper_full_get_segment_t0(ctx, i),
                            t1Cs: whisper_full_get_segment_t1(ctx, i)
                        ))
                    }
                    cont.resume(returning: out)
                }
            }
        }
    }

    // MARK: - Hallucination scrubbing

    private static let hallucinationPatterns: [NSRegularExpression] = {
        // Patterns that whisper often invents when fed silence / noise:
        //   (字幕君: ...) / (字幕组: ...) / 字幕由 XX 提供 / 请订阅 XX 频道 / 感谢观看
        // Both fullwidth (（）) and halfwidth ( () ) parens are covered.
        let raw = [
            #"[（(][^）)]*?(?:字幕|字幕君|字幕组|订阅|频道|翻译|MingHau|Amara)[^）)]*?[）)]"#,
            #"(?:中文)?字幕由[^，。,.！!？?\s]+(?:提供|制作|翻译)[，。.,]?"#,
            #"(?:翻译|校对|时间轴|后期)[:：][^，。,.！!？?\n]+"#,
            #"请订阅[^，。,.！!？?\n]+(?:频道)?[，。.,!?]?"#,
            #"(?:感谢|谢谢)(?:大家)?(?:的)?观看[，。.,!?]?"#,
            #"[（(]\s*[）)]"#,  // empty leftover parens after stripping
            // Belt-and-suspenders: if a previous build's initial_prompt ever
            // leaks back as transcription, scrub it.
            #"(?:以下是)?用户口述的(?:任务)?(?:说明)?[，。.,]?"#,
        ]
        return raw.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    static func removeHallucinations(_ text: String) -> String {
        var s = text
        for re in hallucinationPatterns {
            s = re.stringByReplacingMatches(
                in: s,
                range: NSRange(s.startIndex..., in: s),
                withTemplate: ""
            )
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
