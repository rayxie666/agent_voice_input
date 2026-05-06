import AppKit
import Combine
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    enum State: Equatable {
        case idle
        case recording(Mode)
        case transcribing
        case polishing
        case error(String)
    }
    enum Mode: String, Equatable { case raw, polish }

    @Published var state: State = .idle
    @Published var lastTranscription: String = ""
    @Published var lastPolished: String = ""
    @Published var levels: [Float] = Array(repeating: 0, count: 60)
    @Published var modelLoaded: Bool = false
    @Published var modelLoadError: String?
    @Published var hasAccessibility: Bool = false

    let recorder = AudioRecorder()
    private var whisper: WhisperEngine?
    private let polisher = ClaudePolisher()
    private let settings = AppSettings.shared
    private var hotkeys: HotkeyManager?
    private var cancellables: Set<AnyCancellable> = []
    private var accessibilityTimer: Timer?
    private let ducker = SystemVolumeDucker()
    private let streaming = StreamingSession()
    private var streamingTimer: Timer?
    private var polishBubble: PolishBubble?
    /// Char count of whatever raw transcript was last typed at the cursor —
    /// used as the backspace count when the user asks to polish in place.
    private var lastTypedCharCount: Int = 0

    init() {
        recorder.onLevel = { [weak self] level in
            guard let self = self else { return }
            self.levels.removeFirst()
            self.levels.append(level)
        }

        let manager = HotkeyManager { [weak self] action in
            Task { @MainActor in self?.handleHotkey(action) }
        }
        manager.rebind(
            raw: settings.rawHotkey,
            polish: settings.polishHotkey,
            polishLast: settings.polishLastHotkey)
        self.hotkeys = manager

        settings.$hotkeyVersion
            .sink { [weak self, weak settings] _ in
                guard let s = settings else { return }
                self?.hotkeys?.rebind(
                    raw: s.rawHotkey,
                    polish: s.polishHotkey,
                    polishLast: s.polishLastHotkey)
            }
            .store(in: &cancellables)

        polishBubble = PolishBubble { [weak self] in
            Task { @MainActor in self?.polishLastTyped() }
        }

        loadModel()
        startAccessibilityWatcher()
    }

    /// macOS doesn't fire a notification when the user toggles Accessibility
    /// permission — poll once a second so the UI banner clears as soon as
    /// they grant it (no relaunch required for the indicator to update).
    private func startAccessibilityWatcher() {
        hasAccessibility = Pasteboard.hasAccessibility(prompt: false)
        accessibilityTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let trusted = Pasteboard.hasAccessibility(prompt: false)
                if trusted != self.hasAccessibility { self.hasAccessibility = trusted }
            }
        }
    }

    func loadModel() {
        let path = settings.modelPath
        Task.detached { [weak self] in
            do {
                let engine = try WhisperEngine(modelPath: path)
                await MainActor.run {
                    self?.whisper = engine
                    self?.modelLoaded = true
                    self?.modelLoadError = nil
                }
            } catch {
                await MainActor.run {
                    self?.modelLoaded = false
                    self?.modelLoadError = error.localizedDescription
                }
            }
        }
    }

    /// Hotkey entry point (toggle mode): first press starts recording, second
    /// press of the same hotkey stops + processes.
    func handleHotkey(_ action: HotkeyManager.Action) {
        // "Polish last" is independent of recording state — it operates on
        // text that's already on screen, not on a recording session.
        if action == .polishLast {
            polishLastTyped()
            return
        }
        let mode: Mode = (action == .raw) ? .raw : .polish
        switch state {
        case .idle:
            startRecording(mode: mode)
        case .recording(let current):
            if current == mode {
                stopAndProcess(mode: mode)
            } else {
                _ = recorder.stop()
                ducker.restore()
                startRecording(mode: mode)
            }
        case .transcribing, .polishing:
            NSSound.beep()
        case .error:
            startRecording(mode: mode)
        }
    }

    private func startRecording(mode: Mode) {
        guard whisper != nil else {
            state = .error(modelLoadError ?? "Whisper model not loaded")
            return
        }
        // Stop showing the previous bubble — its lastTypedCharCount reference
        // is about to become stale.
        polishBubble?.hide()
        do {
            if settings.duckOtherAudio {
                ducker.duck(toFraction: settings.duckedVolumeFraction)
            }
            if settings.playFeedbackSounds {
                FeedbackSounds.playStart()
            }
            try recorder.start()
            state = .recording(mode)
            if mode == .raw && settings.streamWhileSpeaking {
                streaming.reset()
                self.lastTranscription = ""
                self.lastTypedCharCount = 0
                startStreamingLoop()
            }
        } catch {
            ducker.restore()
            state = .error("Microphone start failed: \(error.localizedDescription)")
        }
    }

    private func stopAndProcess(mode: Mode) {
        stopStreamingLoop()
        let samples = recorder.stop()
        if settings.playFeedbackSounds {
            FeedbackSounds.playStop()
        }
        ducker.restore()

        Task {
            do {
                guard let whisper = whisper else { throw WhisperError.initFailed }

                switch mode {
                case .raw where settings.streamWhileSpeaking:
                    self.state = .transcribing
                    let tail = await streaming.finalize(
                        allSamples: samples,
                        whisper: whisper,
                        language: settings.language)
                    if !tail.isEmpty {
                        Pasteboard.injectIfAllowed(tail)
                        self.lastTranscription += tail
                    }
                    self.lastTypedCharCount = self.lastTranscription.count
                    self.state = .idle
                    self.maybeShowPolishBubble()

                case .raw:
                    self.state = .transcribing
                    let text = try await whisper.transcribe(
                        samples: samples, language: settings.language)
                    self.lastTranscription = text
                    Pasteboard.paste(text)
                    self.lastTypedCharCount = text.count
                    self.state = .idle
                    self.maybeShowPolishBubble()

                case .polish:
                    self.state = .transcribing
                    let text = try await whisper.transcribe(
                        samples: samples, language: settings.language)
                    self.lastTranscription = text
                    self.state = .polishing
                    let polished = try await self.polisher.polish(
                        text, systemPrompt: settings.polishSystemPrompt)
                    self.lastPolished = polished
                    Pasteboard.paste(polished)
                    self.state = .idle
                }
            } catch {
                self.state = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Streaming loop

    private func startStreamingLoop() {
        streamingTimer?.invalidate()
        streamingTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5, repeats: true
        ) { [weak self] _ in
            self?.streamingTick()
        }
    }

    private func stopStreamingLoop() {
        streamingTimer?.invalidate()
        streamingTimer = nil
    }

    private func streamingTick() {
        guard case .recording(.raw) = state else { return }
        guard let whisper = whisper else { return }
        let snapshot = recorder.snapshot()
        let lang = settings.language
        let lag = settings.streamingLagSeconds
        Task { @MainActor in
            if let chunk = await streaming.step(
                allSamples: snapshot,
                whisper: whisper,
                language: lang,
                lagSeconds: lag)
            {
                Pasteboard.injectIfAllowed(chunk)
                self.lastTranscription += chunk
            }
        }
    }

    // MARK: - In-place polish

    private func maybeShowPolishBubble() {
        guard settings.showPolishBubble else { return }
        guard !lastTranscription.isEmpty else { return }
        guard Pasteboard.hasAccessibility(prompt: false) else { return }
        polishBubble?.show()
    }

    /// User clicked the bubble or pressed the polish-last hotkey. We polish
    /// only the *last sentence* of the session — not the full transcript —
    /// because in long streaming sessions the user is typically iterating on
    /// one thought at a time and re-polishing 5 minutes of history is both
    /// slow and destructive of context they wanted to keep.
    func polishLastTyped() {
        polishBubble?.hide()
        let raw = lastTranscription
        guard !raw.isEmpty else { NSSound.beep(); return }

        guard let range = Self.lastSentenceRange(in: raw) else {
            NSSound.beep(); return
        }
        let target = String(raw[range])
        let prefix = String(raw[raw.startIndex..<range.lowerBound])
        let backspaceCount = target.count
        guard backspaceCount > 0 else { NSSound.beep(); return }

        guard Pasteboard.hasAccessibility(prompt: false) else {
            NSSound.beep()
            state = .error("Accessibility 未授权，无法替换光标处文字")
            return
        }
        if case .polishing = state { return }

        // Optimistically commit the new total so a stale streaming chunk
        // arriving mid-polish can't append on top of the wrong baseline.
        lastTranscription = prefix
        lastTypedCharCount = 0
        state = .polishing

        Task.detached { [polisher, settings, target, prefix, backspaceCount] in
            Pasteboard.sendBackspaces(backspaceCount)
            do {
                let polished = try await polisher.polish(
                    target, systemPrompt: settings.polishSystemPrompt)
                await MainActor.run {
                    self.lastPolished = polished
                    Pasteboard.injectIfAllowed(polished)
                    let newTranscription = prefix + polished
                    self.lastTranscription = newTranscription
                    self.lastTypedCharCount = newTranscription.count
                    self.state = .idle
                }
            } catch {
                // Restore the original sentence so the user isn't left with
                // a hole where their last sentence used to be.
                await MainActor.run {
                    Pasteboard.injectIfAllowed(target)
                    let restored = prefix + target
                    self.lastTranscription = restored
                    self.lastTypedCharCount = restored.count
                    self.state = .error("润色失败：\(error.localizedDescription)")
                }
            }
        }
    }

    /// Find the range of the last sentence in `text`. A sentence boundary is
    /// any of 。！？.!? or a newline. If the text ends with a terminator, the
    /// "last sentence" is the one ending at that terminator (terminator
    /// included). If there are no terminators, the entire text is one sentence.
    private static func lastSentenceRange(in text: String) -> Range<String.Index>? {
        guard !text.isEmpty else { return nil }
        let terminators: Set<Character> = ["。", "！", "？", ".", "!", "?", "\n"]

        // Skip trailing terminators + whitespace so we don't mistake the
        // terminator that *ends* the last sentence for the boundary that
        // *starts* it.
        var lastSig = text.endIndex
        while lastSig > text.startIndex {
            let prev = text.index(before: lastSig)
            if terminators.contains(text[prev]) || text[prev].isWhitespace {
                lastSig = prev
            } else {
                break
            }
        }
        // Walk back from the last significant char to the previous terminator;
        // everything from "after that terminator" through the actual end of
        // the string is the last sentence (terminator + trailing whitespace
        // are deliberately included so the polish target is a clean unit).
        var probe = lastSig
        while probe > text.startIndex {
            let prev = text.index(before: probe)
            if terminators.contains(text[prev]) {
                return probe..<text.endIndex
            }
            probe = prev
        }
        return text.startIndex..<text.endIndex
    }
}
