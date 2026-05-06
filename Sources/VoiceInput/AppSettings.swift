import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var rawHotkey:        KeyCombo { didSet { save(\.rawHotkey,        forKey: "rawHotkey")        } }
    @Published var polishHotkey:     KeyCombo { didSet { save(\.polishHotkey,     forKey: "polishHotkey")     } }
    @Published var polishLastHotkey: KeyCombo { didSet { save(\.polishLastHotkey, forKey: "polishLastHotkey") } }
    @Published var showPolishBubble: Bool {
        didSet { ud.set(showPolishBubble, forKey: "showPolishBubble") }
    }
    @Published var modelPath:    String   { didSet { ud.set(modelPath, forKey: "modelPath") } }
    @Published var language:     String   { didSet { ud.set(language,  forKey: "language")  } }
    @Published var polishSystemPrompt: String {
        didSet { ud.set(polishSystemPrompt, forKey: "polishSystemPrompt") }
    }
    @Published var playFeedbackSounds: Bool {
        didSet { ud.set(playFeedbackSounds, forKey: "playFeedbackSounds") }
    }
    @Published var duckOtherAudio: Bool {
        didSet { ud.set(duckOtherAudio, forKey: "duckOtherAudio") }
    }
    @Published var duckedVolumeFraction: Double {
        didSet { ud.set(duckedVolumeFraction, forKey: "duckedVolumeFraction") }
    }
    @Published var streamWhileSpeaking: Bool {
        didSet { ud.set(streamWhileSpeaking, forKey: "streamWhileSpeaking") }
    }
    @Published var streamingLagSeconds: Double {
        didSet { ud.set(streamingLagSeconds, forKey: "streamingLagSeconds") }
    }

    /// Emitted by AppSettingsView when the user finishes editing a hotkey, so the
    /// HotkeyManager can rebind without spamming registrations on every keystroke.
    @Published var hotkeyVersion: Int = 0

    private let ud = UserDefaults.standard

    static let defaultPolishPrompt = """
        你是一个 prompt 工程师。下面是用户口述的、可能零散或口语化的 \
        任务描述。请把它改写成一段结构化、详细、AI 容易直接执行的 prompt。\
        要求：\n\
        1. 保留用户的核心意图，不要无中生有添加新需求。\n\
        2. 把模糊的指代、省略的对象明确出来；补全约束、输入输出格式、\
        成功标准。\n\
        3. 如果是写代码任务，明确语言、运行环境、边界条件。\n\
        4. 直接输出改写后的 prompt 本身，不要解释、不要寒暄、不要使用 \
        markdown 代码块包裹。
        """

    private init() {
        self.rawHotkey        = AppSettings.loadCombo(forKey: "rawHotkey",        default: .recordRaw)
        self.polishHotkey     = AppSettings.loadCombo(forKey: "polishHotkey",     default: .recordPolish)
        self.polishLastHotkey = AppSettings.loadCombo(forKey: "polishLastHotkey", default: .polishLast)
        self.showPolishBubble = ud.object(forKey: "showPolishBubble") as? Bool ?? true
        // If the saved path is missing on disk (eg. an earlier broken default),
        // re-run discovery rather than silently keeping a dead path.
        if let saved = ud.string(forKey: "modelPath"),
           FileManager.default.fileExists(atPath: saved) {
            self.modelPath = saved
        } else {
            self.modelPath = AppSettings.discoverDefaultModelPath()
        }
        self.language     = ud.string(forKey: "language")  ?? "auto"
        self.polishSystemPrompt =
            ud.string(forKey: "polishSystemPrompt") ?? AppSettings.defaultPolishPrompt
        self.playFeedbackSounds =
            ud.object(forKey: "playFeedbackSounds") as? Bool ?? true
        self.duckOtherAudio =
            ud.object(forKey: "duckOtherAudio") as? Bool ?? true
        let storedFraction = ud.object(forKey: "duckedVolumeFraction") as? Double
        self.duckedVolumeFraction = storedFraction ?? 0.25
        self.streamWhileSpeaking =
            ud.object(forKey: "streamWhileSpeaking") as? Bool ?? true
        let storedLag = ud.object(forKey: "streamingLagSeconds") as? Double
        self.streamingLagSeconds = storedLag ?? 1.5
    }

    /// Find a sensible default model location at first launch. Probed in order:
    ///   1. ~/Library/Application Support/VoiceInput/Models/ggml-medium.bin
    ///   2. <repo>/Models/ggml-medium.bin (dev mode: walk up from the .app bundle)
    /// Falls back to (1) even when missing so the path field shows a stable expected location.
    private static func discoverDefaultModelPath() -> String {
        let fm = FileManager.default
        let appSupport = NSString(
            string: "~/Library/Application Support/VoiceInput/Models/ggml-medium.bin"
        ).expandingTildeInPath
        if fm.fileExists(atPath: appSupport) { return appSupport }

        // Walk up from the .app bundle (build/VoiceInput.app/Contents/MacOS/VoiceInput)
        // looking for a sibling Models/ggml-medium.bin in dev layouts.
        var dir = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<5 {
            let candidate = dir.appendingPathComponent("Models/ggml-medium.bin").path
            if fm.fileExists(atPath: candidate) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return appSupport
    }

    private static func loadCombo(forKey key: String, default fallback: KeyCombo) -> KeyCombo {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(KeyCombo.self, from: data)
        else { return fallback }
        return decoded
    }

    private func save<V: Codable>(_ keyPath: KeyPath<AppSettings, V>, forKey key: String) {
        let value = self[keyPath: keyPath]
        if let data = try? JSONEncoder().encode(value) {
            ud.set(data, forKey: key)
        }
    }

    /// Tell observers (HotkeyManager) to rebind.
    func bumpHotkeyVersion() { hotkeyVersion &+= 1 }
}
