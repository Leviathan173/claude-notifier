# Claude Code Windows Notifier

Windows 桌面通知系统，为 Claude Code 提供三种协同提醒：

- **屏幕左右边缘的呼吸光条**（全屏，5 秒，可穿透点击）
- **右下角 popup 弹窗**（5 秒后自动消失，可穿透点击）
- **自定义 wav 提示音**（默认使用 Windows Proximity Notification）

三者会在 Claude 结束回答、子任务结束、或需要用户输入时**同时**触发，让你不管在做什么都能第一时间发现。

## 触发场景

| 事件 | 消息 | 光条颜色 |
|------|------|---------|
| `Stop` — Claude 完成回答 | "Task completed - Claude waiting" | 🟢 绿色 |
| `SubagentStop` — 子代理任务结束 | "Subagent task completed" | 🟢 绿色 |
| `PreToolUse` (AskUserQuestion) — 需要用户输入 | "Claude needs your input" | 🟡 黄色 |

## 快速开始

### 部署 / 更新

```powershell
.\deploy.ps1
```

脚本会：

1. 把 `src/*` 复制到 `~/.claude/scripts/`
2. 用 `merge-hooks.js` 把 6 个 hooks（3 个事件 × 2 个脚本：通知 + 光条）合并进 `~/.claude/settings.json`
3. 已有的 hook 会被跳过，其他 hooks 不会被动到

**部署完成后需要重启 Claude Code**，才会重新加载 `settings.json`。

### 卸载

```powershell
.\deploy.ps1 -Uninstall
```

从 `settings.json` 移除本项目注册的 hooks 并删除已安装的脚本。其他 hook 保持不动。

### 手动测试

```powershell
# 单独触发一次 popup + 声音
& "$env:USERPROFILE\.claude\scripts\hook-wrapper.cmd" "手动测试"

# 单独触发一次呼吸光条（黄色）
& "$env:USERPROFILE\.claude\scripts\hook-wrapper-flash.cmd" "手动测试" "Yellow"
```

日志在 `%TEMP%\claude-notifier.log`。

## 要求

- Windows 10 / 11
- PowerShell 5.1+（Windows 自带即可，不需要 PowerShell 7）
- Node.js（仅 `deploy.ps1` 需要，用于安全合并 `settings.json`）
- Claude Code（已安装并已初始化 `~/.claude/settings.json`）

**运行时零外部依赖** —— 通知本身只用 .NET Framework 内置的 WPF 和 `System.Media.SoundPlayer`。

## 文件结构

```
claude-notifier/
├── src/
│   ├── show-notification.ps1   # popup 弹窗 + wav 声音
│   ├── flash-glow.ps1          # 全屏左右呼吸光条
│   ├── hook-wrapper.cmd        # popup+声音 hook 入口
│   ├── hook-wrapper-flash.cmd  # 光条 hook 入口
│   ├── notification.wav        # 默认提示音
│   └── merge-hooks.js          # 部署时合并 settings.json 的 Node 脚本
├── deploy.ps1                  # 一键部署 / 卸载
├── .gitignore
└── README.md
```

## 工作原理

### 通知触发链路

```
Claude Code                      settings.json                  hook 入口 (.cmd)              PowerShell 脚本
─────────                       ─────────────                  ───────────────              ────────────────
Stop 事件 ────► matcher 匹配 ──► cmd /c hook-wrapper.cmd ──────► show-notification.ps1 ──► popup + wav 声音
                              └► cmd /c hook-wrapper-flash.cmd ─► flash-glow.ps1 ────────► 全屏呼吸光条
```

两个 hook **并行触发** —— 光条更简单所以稍微早一点点出现（几十毫秒差距）。

### popup + 声音的顺序

`show-notification.ps1` 里，声音播放放在 popup 窗口的 `Loaded` 回调中，用 `SoundPlayer.Play()` 异步播放。所以顺序是：

1. WPF 加载 XAML → popup 渲染出来
2. `Loaded` 事件触发 → 声音开始播（异步，不阻塞 UI）
3. 5 秒后 popup 自动关闭

流程期间 popup 的 `ShowDialog` 让 PowerShell 进程持续存活 5 秒，2 秒的 wav 能完整播完不会被截断。

### 点击穿透

`flash-glow.ps1` 和 `show-notification.ps1` 的 popup 都是无边框透明 WPF 窗口。WPF 的 `IsHitTestVisible='False'` 只影响 WPF 内部的命中测试，**不会**让底层 HWND 对鼠标透明 —— 所以两个脚本都在窗口 `Loaded` 时通过 P/Invoke 给 `GWL_EXSTYLE` 追加 `WS_EX_TRANSPARENT | WS_EX_LAYERED`，让鼠标点击穿透到下方窗口。

### hook 配置形式

`merge-hooks.js` 用的是 Claude Code 的 **exec form** hook（`command` + `args` 数组），而不是 shell form（拼接命令行字符串）。exec form 直接 spawn 进程不走 shell 展开，彻底避开引号转义问题 —— 之前踩过 shell form 里 Windows 路径反斜杠 + JSON 转义 + PowerShell 参数三层嵌套导致的各种奇葩问题。

### 为什么要用 Node 合并 settings.json

早期版本用 PowerShell 的 `ConvertFrom-Json` / `ConvertTo-Json` 合并，但 Claude Code 的 `settings.json` 里有嵌套很深的 `enabledPlugins` / `extraKnownMarketplaces` 等对象，PowerShell 的 JSON 转换会把它们展平或改变类型。改用 Node.js 内置的 `JSON.parse` / `JSON.stringify` 后就稳定了。

## 自定义

### 改提示音

替换 `src/notification.wav` 为任意 PCM 格式的 wav 文件（不支持压缩 wav，`System.Media.SoundPlayer` 只吃 PCM），然后重新 `.\deploy.ps1`。

### 改光条颜色 / 时长 / 频率

编辑 `src/flash-glow.ps1`：

```powershell
$Bar = 250      # 光条宽度（像素）
$Dur = 5000     # 总时长（毫秒）
$Cyc = 2        # 5 秒内的呼吸周期数
```

### 改 popup 位置 / 样式

编辑 `src/show-notification.ps1` 里 `Show-Popup` 函数的 XAML —— `Left`/`Top` 控制位置，`Border` 的 `Background`/`BorderBrush` 控制配色。

## 故障排查

**没触发**：查 `%TEMP%\hook-triggered.txt`（hook 入口 .cmd 会写这个）—— 如果没记录，说明 Claude Code 没调用 hook，很可能是 `settings.json` 里没有对应 event 的注册。用 `.\deploy.ps1` 重装 hooks 并**重启 Claude Code**。

**有 hook 记录但没通知**：查 `%TEMP%\claude-notifier.log` —— PowerShell 脚本每步都会写日志，`SOUND FAIL` / `POPUP FAIL` / `FLASH FAIL` 会告诉你哪一步炸了。

**声音听不到但日志正常**：确认 `src/notification.wav` 是 PCM 格式；用 `powershell -c "(New-Object System.Media.SoundPlayer '$env:USERPROFILE\.claude\scripts\notification.wav').PlaySync()"` 单独测。

**通知遮挡了鼠标点击**：应该已经解决（`WS_EX_TRANSPARENT`）—— 如果还有问题，确认部署的 `flash-glow.ps1` 和 `show-notification.ps1` 是最新版本（`diff` 一下 `src/` 和 `~/.claude/scripts/`）。
