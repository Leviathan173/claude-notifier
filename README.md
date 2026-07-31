# Claude Code Windows Notifier

Windows 桌面通知系统，为 **Claude Code** 和 **OpenCode** 提供三种协同提醒：

- **屏幕左右边缘的呼吸光条**（全屏，5 秒，可穿透点击）
- **右下角 popup 弹窗**（5 秒后自动消失，可穿透点击）
- **自定义 wav 提示音**

---

## 支持的平台

| 平台 | 部署方式 | 触发事件 |
|------|---------|---------|
| Claude Code | `settings.json` hooks | `Stop`, `SubagentStop`, `PreToolUse` |
| OpenCode | 插件 (`plugins/`) | `message.updated` (finish=stop) |

---

## Claude Code 部署

### 安装 / 更新

```powershell
.\deploy.ps1
```

脚本会把 `src/*` 复制到 `~/.claude/scripts/`，并用 `merge-hooks.js` 把 hooks 合并进 `~/.claude/settings.json`。

### 卸载

```powershell
.\deploy.ps1 -Uninstall
```

### 触发事件

| 事件 | 消息 | 光条颜色 |
|------|------|---------|
| `Stop` — Claude 完成回答 | "Task completed - Claude waiting" | 🟢 绿色 |
| `SubagentStop` — 子代理任务结束 | "Subagent task completed" | 🟢 绿色 |
| `PreToolUse` (AskUserQuestion) — 需要用户输入 | "Claude needs your input" | 🟡 黄色 |

### 手动测试

```powershell
# 单独触发一次 popup + 声音
& "$env:USERPROFILE\.claude\scripts\hook-wrapper.cmd" "手动测试"

# 单独触发一次呼吸光条（黄色）
& "$env:USERPROFILE\.claude\scripts\hook-wrapper-flash.cmd" "手动测试" "Yellow"
```

---

## OpenCode 部署

### 安装 / 更新

```powershell
.\deploy-opencode.ps1
```

脚本会把插件和脚本复制到 `~/.config/opencode/`：

- `plugins/opencode-notifier.js` — 插件主文件
- `scripts/show-notification.ps1` — popup 弹窗 + 声音
- `scripts/flash-glow.ps1` — 呼吸光条
- `scripts/notification.wav` — 默认提示音

### 卸载

```powershell
.\deploy-opencode.ps1 -Uninstall
```

### 触发机制

插件监听 OpenCode 事件，当 **assistant 消息完成**（`message.updated` + `finish=stop`）时，同时触发：
- WPF 弹窗 + 提示音
- 绿色呼吸光条

---

## 要求

- Windows 10 / 11
- PowerShell 5.1+（Windows 自带）
- Node.js（仅 `deploy.ps1` 需要，用于合并 `settings.json`）
- Claude Code 或 OpenCode

---

## 文件结构

```
claude-notifier/
├── src/
│   ├── show-notification.ps1    # popup 弹窗 + wav 声音
│   ├── flash-glow.ps1           # 全屏左右呼吸光条
│   ├── hook-wrapper.cmd         # popup+声音 hook 入口 (Claude Code)
│   ├── hook-wrapper-flash.cmd   # 光条 hook 入口 (Claude Code)
│   ├── notification.wav         # 默认提示音
│   ├── merge-hooks.js           # 部署时合并 settings.json 的 Node 脚本
│   └── opencode-notifier.js     # OpenCode 插件
├── deploy.ps1                   # Claude Code 一键部署 / 卸载
├── deploy-opencode.ps1          # OpenCode 一键部署 / 卸载
├── .gitignore
└── README.md
```

---

## 工作原理

### Claude Code 通知链路

```
Claude Code                  settings.json                  hook 入口 (.cmd)              PowerShell 脚本
─────────                   ─────────────                  ───────────────              ────────────────
Stop 事件 ────► matcher 匹配 ──► cmd /c hook-wrapper.cmd ──────► show-notification.ps1 ──► popup + wav 声音
                               └► cmd /c hook-wrapper-flash.cmd ─► flash-glow.ps1 ────────► 全屏呼吸光条
```

两个 hook **并行触发** —— 光条更简单所以稍微早一点点出现（几十毫秒差距）。

### OpenCode 通知链路

```
OpenCode 事件系统 ──► opencode-notifier.js 插件
                              │
                              ├─ 监听 message.updated (finish=stop)
                              │
                              ├─ show-notification.ps1 ──► popup + wav 声音
                              └─ flash-glow.ps1 ─────────► 绿色呼吸光条
```

### popup + 声音的顺序

`show-notification.ps1` 里，声音播放放在 popup 窗口的 `Loaded` 回调中，用 `SoundPlayer.Play()` 异步播放：

1. WPF 加载 XAML → popup 渲染出来
2. `Loaded` 事件触发 → 声音开始播（异步，不阻塞 UI）
3. 5 秒后 popup 自动关闭

### 点击穿透

两个脚本都通过 P/Invoke 给 `GWL_EXSTYLE` 追加 `WS_EX_TRANSPARENT | WS_EX_LAYERED`，让鼠标点击穿透到下方窗口。

---

## 自定义

### 改提示音

替换 `src/notification.wav` 为任意 PCM 格式的 wav 文件，然后重新部署。

### 改光条颜色 / 时长 / 频率

编辑 `src/flash-glow.ps1`：

```powershell
$Bar = 250      # 光条宽度（像素）
$Dur = 5000     # 总时长（毫秒）
$Cyc = 2        # 5 秒内的呼吸周期数
```

### 改 popup 位置 / 样式

编辑 `src/show-notification.ps1` 里 `Show-Popup` 函数的 XAML。

---

## 故障排查

**没触发**：查 `%TEMP%\hook-triggered.txt`（Claude Code）或 `%USERPROFILE%\opencode-notifier-debug.log`（OpenCode）。

**有记录但没通知**：查 `%TEMP%\claude-notifier.log` —— `SOUND FAIL` / `POPUP FAIL` / `FLASH FAIL` 会告诉你哪一步出错。

**声音听不到但日志正常**：确认 `notification.wav` 是 PCM 格式。
