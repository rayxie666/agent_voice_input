import SwiftUI

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !coordinator.hasAccessibility {
                accessibilityBanner
            }

            HStack {
                statusDot
                Text(stateLabel).font(.headline)
                Spacer()
            }

            WaveformView(levels: coordinator.levels)
                .frame(height: 36)

            if !coordinator.lastTranscription.isEmpty {
                Divider()
                Group {
                    Text("最近转写").font(.caption).foregroundStyle(.secondary)
                    Text(coordinator.lastTranscription)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }
            if !coordinator.lastPolished.isEmpty {
                Group {
                    Text("最近润色").font(.caption).foregroundStyle(.secondary)
                    Text(coordinator.lastPolished)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(6)
                        .textSelection(.enabled)
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                hotkeyRow(label: "原文转写", combo: settings.rawHotkey)
                hotkeyRow(label: "润色为 Prompt", combo: settings.polishHotkey)
                hotkeyRow(label: "润色刚说的话", combo: settings.polishLastHotkey)
            }

            HStack {
                Button("打开设置…") {
                    NSApp.activate(ignoringOtherApps: true)
                    if #available(macOS 14, *) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }

            if let err = coordinator.modelLoadError {
                Text("模型未加载：\(err)").font(.caption).foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private var accessibilityBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("辅助功能未授权").font(.headline)
            }
            Text("没有这个权限，转写完的文字没法自动落到光标处（只能放到剪贴板让你 ⌘V）。授权后必须**重启 App** 才生效。")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            HStack {
                Button("打开授权页") { Pasteboard.openAccessibilityPane() }
                Button("退出 App") { NSApp.terminate(nil) }
                    .help("授权后从 build/VoiceInput.app 重新启动")
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
    }

    private var statusDot: some View {
        Circle()
            .fill(stateColor)
            .frame(width: 10, height: 10)
    }

    private var stateLabel: String {
        switch coordinator.state {
        case .idle:                  return coordinator.modelLoaded ? "Idle" : "加载模型中…"
        case .recording(let m):      return m == .raw ? "录音中（原文）" : "录音中（润色）"
        case .transcribing:          return "转写中…"
        case .polishing:             return "Claude 润色中…"
        case .error(let s):          return "错误：\(s)"
        }
    }

    private var stateColor: Color {
        switch coordinator.state {
        case .idle:         return coordinator.modelLoaded ? .green : .gray
        case .recording:    return .red
        case .transcribing: return .orange
        case .polishing:    return .blue
        case .error:        return .pink
        }
    }

    @ViewBuilder
    private func hotkeyRow(label: String, combo: KeyCombo) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(combo.displayString).font(.system(.body, design: .monospaced))
        }
        .font(.caption)
    }
}

private struct WaveformView: View {
    let levels: [Float]

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    let h = max(2, CGFloat(level) * geo.size.height * 1.6)
                    Capsule()
                        .fill(Color.accentColor.opacity(0.7))
                        .frame(width: max(2, (geo.size.width / CGFloat(levels.count)) - 2),
                               height: min(geo.size.height, h))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}
