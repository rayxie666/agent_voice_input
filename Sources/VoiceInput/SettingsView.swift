import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("基本", systemImage: "gearshape") }
            polishTab
                .tabItem { Label("润色", systemImage: "wand.and.stars") }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }

    private var generalTab: some View {
        Form {
            Section("快捷键") {
                LabeledContent("原文转写") {
                    HotkeyRecorderField(combo: Binding(
                        get: { settings.rawHotkey },
                        set: { settings.rawHotkey = $0; settings.bumpHotkeyVersion() }
                    ))
                    .frame(width: 160, height: 24)
                }
                LabeledContent("润色为 Prompt") {
                    HotkeyRecorderField(combo: Binding(
                        get: { settings.polishHotkey },
                        set: { settings.polishHotkey = $0; settings.bumpHotkeyVersion() }
                    ))
                    .frame(width: 160, height: 24)
                }
                LabeledContent("润色刚说的话（不再录新音频）") {
                    HotkeyRecorderField(combo: Binding(
                        get: { settings.polishLastHotkey },
                        set: { settings.polishLastHotkey = $0; settings.bumpHotkeyVersion() }
                    ))
                    .frame(width: 160, height: 24)
                }
                Toggle("说完后在鼠标位置浮一个「润色」气泡",
                       isOn: $settings.showPolishBubble)
                Text("点击输入框后按下你想要的组合键。需要至少一个修饰键（⌃/⌥/⇧/⌘）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("识别语言") {
                Picker("语言", selection: $settings.language) {
                    Text("自动检测").tag("auto")
                    Text("中文").tag("zh")
                    Text("英文").tag("en")
                }
                .pickerStyle(.segmented)
            }

            Section("实时输入") {
                Toggle("边说边出字（流式转写）", isOn: $settings.streamWhileSpeaking)
                if settings.streamWhileSpeaking {
                    HStack {
                        Text("延迟")
                        Slider(value: $settings.streamingLagSeconds,
                               in: 0.5...3.0, step: 0.1)
                            .frame(width: 160)
                        Text("\(settings.streamingLagSeconds, specifier: "%.1f")s")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 44, alignment: .trailing)
                    }
                    .font(.caption)
                    Text("延迟越短越「实时」，但 whisper 修订的概率越大、字可能闪烁；越长越稳。润色快捷键不受此影响（始终一次出全文）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("反馈与背景音") {
                Toggle("录音开始/结束播放提示音", isOn: $settings.playFeedbackSounds)
                Toggle("录音时降低系统音量（避免和正在播放的视频/音乐冲突）",
                       isOn: $settings.duckOtherAudio)
                if settings.duckOtherAudio {
                    HStack {
                        Text("降到当前音量的")
                        Slider(value: $settings.duckedVolumeFraction,
                               in: 0.0...1.0, step: 0.05)
                            .frame(width: 160)
                        Text("\(Int(settings.duckedVolumeFraction * 100))%")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 44, alignment: .trailing)
                    }
                    .font(.caption)
                }
            }

            Section("Whisper 模型") {
                LabeledContent("路径") {
                    HStack {
                        TextField("", text: $settings.modelPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                        Button("选择…") { pickModel() }
                        Button("重载") { coordinator.loadModel() }
                    }
                }
                Text(coordinator.modelLoaded
                     ? "已加载"
                     : "未加载：\(coordinator.modelLoadError ?? "等待中…")")
                    .font(.caption)
                    .foregroundStyle(coordinator.modelLoaded ? .green : .red)
            }
        }
    }

    private var polishTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("润色 system prompt")
                .font(.headline)
            Text("会通过 `claude -p '<这段 prompt>'` 调用，转写文本通过 stdin 传入。")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $settings.polishSystemPrompt)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 240)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )
            HStack {
                Spacer()
                Button("恢复默认") {
                    settings.polishSystemPrompt = AppSettings.defaultPolishPrompt
                }
            }
        }
    }

    private func pickModel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择 ggml 模型文件 (e.g. ggml-medium.bin)"
        if panel.runModal() == .OK, let url = panel.url {
            settings.modelPath = url.path
            coordinator.loadModel()
        }
    }
}
