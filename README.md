# VoiceInput — Mac 语音输入 + Claude 润色

一个常驻菜单栏的 macOS 工具：按下全局快捷键开始/停止录音，本地用
[whisper.cpp](https://github.com/ggerganov/whisper.cpp) 流式转写，
直接把字一个一个落到当前光标处。还有第二条路径会把刚说的话交给本地的
`claude -p`（即 Claude Code CLI），改写成更详细、AI 更容易执行的
prompt 后注入进去。

- 完全本地：whisper.cpp + Metal 加速，不上传音频
- 不需要 Claude API key：润色复用你已有的 Claude Code 登录态
- 流式输入：边说边出字，跟系统自带听写一个体验
- 中英混合：默认 `ggml-medium`，多语言识别准确度够日常用
- 全局快捷键、提示音、音量 duck、流式延迟都可调

## 下载（推荐）

去 [Releases 页面](https://github.com/rayxie666/agent_voice_input/releases/latest)
下载 `VoiceInput-<版本>.dmg`：

1. 双击 `.dmg` 挂载 → 把 `VoiceInput` 图标**拖到 `Applications` 文件夹**
2. **首次打开必须右键**：右键 → 「打开」 → 弹窗里再点一次 「打开」
   （没买 Apple Developer 证书做 notarization，macOS Gatekeeper 默认会
   把没注册过的 App 标记成「已损坏」；这一步绕过一次就行，之后双击都正常）
3. 启动后菜单栏出现话筒图标 → 点开 → 一键下载语音识别模型（~1.5 GB）
4. 给麦克风和辅助功能授权（系统会提示）
5. 想用润色功能：终端里能跑 `claude` 命令（Claude Code CLI）即可

## 系统要求

- Apple Silicon Mac（M1 / M2 / M3 / M4 系列）
- macOS 13+
- 想用润色：装好 Claude Code CLI 并登录过

## 从源码构建（开发者）

```bash
# 1. 拉 whisper.cpp、本地编译 Metal 版、下载 ggml-medium.bin (~1.5GB)
make setup

# 2. 编译 Swift app 并打成 VoiceInput.app 包
make app

# 3. 启动
make run
# 或者直接：open build/VoiceInput.app

# 4. 打 release DMG + 上传到 GitHub Releases
make release VERSION=0.1.0
gh release create v0.1.0 build/VoiceInput-0.1.0.dmg --generate-notes
# 或者推 tag 让 .github/workflows/release.yml 自动构建上传：
git tag v0.1.0 && git push origin v0.1.0
```

源码构建额外需要：
- Xcode Command Line Tools (`xcode-select --install`)
- `cmake`：`brew install cmake`
- `create-dmg`（仅打 release 用）：`brew install create-dmg`

首次启动会弹两次系统授权框：

1. **麦克风** — 必须允许，否则没法录音。
2. **辅助功能 (Accessibility)** — 必须允许，App 用它直接把字注入当前焦点应用。
   位置：系统设置 → 隐私与安全性 → 辅助功能 → 添加 / 勾选 VoiceInput。
   授权后**重启 VoiceInput**。
   开发者注意：每次 `make app` 后 cdhash 会变 → 之前的授权失效，跑 `make permit` 重置。

## 使用

| 操作 | 默认快捷键 | 行为 |
| --- | --- | --- |
| 原文转写 | `⌃⌥Space` | 按一下开始录，**边说边一字字出现在光标处**；再按一下停止 |
| 录音 + 一次性润色 | `⌃⌥⇧Space` | 按一下开始录，再按一下停 → `claude -p` 把整段改写成 prompt → 注入 |
| 润色刚说的话 | `⌥P` | 把刚才那段话的**最后一句**送给 claude 润色 → backspace 替换在原位 |
| 润色气泡 | 鼠标点击 | 流式录音结束后鼠标位置自动浮出 `✨ 润色`，点一下等价于 `⌥P` |

快捷键可以在菜单栏 → 「打开设置…」里自由改成你喜欢的组合。

## 工作原理

```
麦克风 ──► AVAudioEngine ──► 16kHz mono float32
                                   │
                                   ▼
                            whisper.cpp (Metal)
                                   │
              ┌────────── 原文 ────┴──── 润色路径 ──────┐
              ▼                                          ▼
        NSPasteboard                         claude -p '<system prompt>'
              │                                          │
              ▼                                          ▼
     CGEvent 模拟 ⌘V          ──── 输出 ─── NSPasteboard + ⌘V
```

模块对应（`Sources/VoiceInput/`）：

| 文件 | 作用 |
| --- | --- |
| `VoiceInputApp.swift` | `@main`、菜单栏 + 设置窗 |
| `AppCoordinator.swift` | 状态机：idle ↔ recording ↔ transcribing ↔ polishing |
| `HotkeyManager.swift` | Carbon `RegisterEventHotKey` 注册全局热键 |
| `AudioRecorder.swift` | AVAudioEngine 抽样并降采样到 16kHz |
| `WhisperEngine.swift` | 桥接 whisper.cpp C API |
| `ClaudePolisher.swift` | 通过 `/bin/zsh -lc 'claude -p ...'` 调 CLI |
| `Pasteboard.swift` | 写剪贴板 + `CGEvent` 发 ⌘V |
| `Settings.swift` | UserDefaults 里的可持久化偏好 |
| `KeyCombo.swift` | 快捷键编码 / 显示 |
| `HotkeyRecorderField.swift` | 设置窗里点击捕获新快捷键的控件 |
| `ContentView.swift` / `SettingsView.swift` | SwiftUI 界面 |

## 自定义润色 prompt

设置窗 →「润色」标签里有一段默认的 system prompt。你可以改成你自己
更偏好的指令风格 —— 例如指定输出格式、特定领域术语、永远附带「使
用 XX 框架/语言」之类的约束。

底层调用形如：

```bash
echo "<转写文本>" | claude -p '<system prompt>'
```

## 常见问题

- **「Whisper model not found」**：检查 `Models/ggml-medium.bin` 是否
  存在，或在设置里把路径改到你下载的位置。
- **快捷键不响应**：Carbon `RegisterEventHotKey` 失败时（多半是被别
  的 App 占用）会在 Console 里打日志。换一个组合试试。
- **粘贴没反应**：辅助功能权限没给。检查系统设置，授权后重启 App。
- **`claude` 找不到**：App 用的是 `/bin/zsh -lc` 登录 shell。如果你
  把 claude 装在了非默认 PATH，请在 `~/.zshrc` 或 `~/.zprofile` 里
  把它加进来。

## 后续方向

- Push-to-talk 模式（按住录音、松开停止）
- 实时流式转写（边说边出字）
- 录音历史记录窗
- 切换到更小的模型（small）省内存

## License

仅供本地使用。
