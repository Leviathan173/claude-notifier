# Claude Code Windows Notifier

Windows 桌面通知系统，为 **Claude Code** 和 **OpenCode** 提供四种协同提醒：

- **屏幕左右边缘的呼吸光条**（全屏，5 秒，可穿透点击）
- **右下角 popup 弹窗**（5 秒后自动消失，可穿透点击）
- **自定义 wav 提示音**
- **Windows Terminal 标签页进度环 + 标题标记**（OpenCode：进行中 ⏳ 转圈、完成 ✅ <会话名>）

---

## 支持的平台

| 平台 | 部署方式 | 触发事件 |
|------|---------|---------|
| Claude Code | `settings.json` hooks | `Stop`, `SubagentStop`, `PreToolUse` |
| OpenCode | TUI 插件（标签环/标题）+ 外部 watcher（光条/声音） | `session.execution.started`, `session.execution.succeeded`/`failed`, `permission.asked`, `form.created` |

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

脚本会写入（OpenCode V2 布局）：

- `plugins/notifier/tui.js` — TUI 插件：标签页进度环 + 标题标记
- `scripts/notify-watcher.ps1` — 常驻 watcher：跟随服务端事件流，触发光条 + 声音
- `scripts/show-notification.ps1` — popup 弹窗 + 声音（Claude Code 用；OpenCode 只用它的 `-Flash` 模式）
- `scripts/flash-glow.ps1` — 呼吸光条
- `scripts/notification.wav` — 默认提示音
- `%APPDATA%\...\Startup\opencode-notifier.vbs` — 开机自启 watcher（无窗口，不需要管理员权限）

部署脚本会顺手删掉 V1 布局的旧插件（`plugins/opencode-notifier.js`、`plugin/opencode-notifier.js`），
并重启已在运行的 watcher。

### 卸载

```powershell
.\deploy-opencode.ps1 -Uninstall
```

会先停掉 watcher，再删除上述文件与自启项。

### 触发机制

| 事件 | 光条 | 标签页 |
|------|------|--------|
| `session.execution.started` — 一轮开始 | — | 转圈 + `⏳ OC \| <会话名>` |
| `session.execution.succeeded` / `session.idle` — 回答完成 | 🟢 绿色 | 清环 + `✅ OC \| <会话名>` |
| `session.execution.failed` — 出错 | 🟡 黄色 | 清环 |
| `permission.asked` / `form.created` — 需要用户操作 | 🟡 黄色 | — |

同一轮里 `session.idle` 和 `session.execution.succeeded` 会前后脚到达，`show-notification.ps1`
里有 2 秒去重（`%TEMP%\claude-notifier.stamp`），只提醒一次。

### 手动测试

```powershell
# 只测光条 + 声音
powershell -STA -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.config\opencode\scripts\show-notification.ps1" -Flash -FlashColor Green -Sound "$env:USERPROFILE\.config\opencode\scripts\notification.wav"

# 端到端测一次（应看到绿光条 + 听到声音）
opencode run -m <任意模型> "ok"
```

---

## 为什么 OpenCode 不再用插件发通知

OpenCode 1.x 的插件里可以直接 `Bun.spawn(["powershell", ...])`。OpenCode 2.x 重写了插件 API，
而且**插件运行时里的 `child_process` 是空壳**：`spawn` / `spawnSync` / `Bun.spawn` 都返回
一个 pid 和退出码 0，实际什么都没启动（`cmd /c echo x >> file` 连文件都不产生）。
所以插件已经无法拉起 PowerShell，光条和声音只能从 OpenCode 外面发。

现在的分工：

```
OpenCode 服务端事件流 (/api/event, SSE)
        │
        ├─► notify-watcher.ps1（常驻，开机自启）
        │      ├─ session.execution.succeeded / session.idle ─────────► 绿色光条 + wav
        │      └─ permission.asked / form.created / execution.failed ─► 黄色光条 + wav
        │
        └─► TUI 插件 plugins/notifier/tui.js（跑在 TUI 进程里）
               └─ session.execution.started/succeeded ──────────────► 标签转圈 + 标题标记
```

watcher 用 `opencode service status` 拿当前服务地址（端口每次启动都可能变），用
`~/.config/opencode/service.json` 里的密码做 basic auth，断线每 5 秒重连，
没有 opencode 在跑时每 10 秒重试一次。

TUI 插件只负责终端里的东西（进度环、标题），它跑在 `opencode.exe` TUI 进程内，
所以 `fs.writeSync(1, ...)` 能直接写进 Windows Terminal 的 ConPTY。

---

## Windows Terminal 标签页进度环（仅 OpenCode）

任务进行时标签页转圈，完成后把环清掉、在标签标题前留一个 ✅ 加会话名，切走再回来
一眼能看到状态。Claude Code 自己会发这个环，无需本插件；OpenCode 的 TUI 没有，
所以由插件补上。

插件挂在 `session.execution.started`（加进"运行中"集合）和
`session.execution.succeeded` / `failed` / `interrupted`（移出集合）上，集合非空就转圈，
清空就清环。一轮里可能只有一次 `started` 和一次 `succeeded`，所以不会闪。
会话名取自 `session.renamed` 的 `data.title`；opencode 自己生成标题后会重设标题，
所以标题变化时插件会重新压上标记。标记常量在 `src/opencode-notifier.js` 顶部，可自行改。

> OSC 9;4 只能画圈，画不了勾：圈负责「进行中」，勾只能放在标签标题里（`✅`），
> 所以完成态是「清环 + 标题带勾」。

实现是 ConEmu 的 `OSC 9;4` 序列。插件与 TUI 同在一个 `opencode.exe` 进程里，所以
直接 `fs.writeSync(1, ...)` 写进进程自己的 stdout（也就是 WT 的 ConPTY）。stdout 不是
TTY 时不写（例如输出被重定向到文件或管道），避免把转义序列混进输出。

> 注意:不要试图另起进程写这个序列。WT 用的是 ConPTY 伪控制台，外部进程
> `AttachConsole` 会返回 `ACCESS_DENIED`，`\\.\CONOUT$` 也打不开。只有持有该
> pty 的 opencode 进程自己能写。

| 状态 | 序列 |
|------|------|
| 进行中 | `ESC]9;4;3;BEL` |
| 完成 / 清除 | `ESC]9;4;0;BEL`（清环，完成态靠标题里的 ✅） |

需要 Windows Terminal ≥ 1.6；标签页进度环不依赖任何设置，任务栏进度需在
「设置 → 辅助功能 → 显示」里开启动画。

---

## 要求

- Windows 10 / 11
- PowerShell 5.1+（Windows 自带）
- Node.js（仅 `deploy.ps1` 需要，用于合并 `settings.json`）
- Claude Code 或 OpenCode 2.x（V2 插件 API）

---

## 文件结构

```
claude-notifier/
├── src/
│   ├── show-notification.ps1    # popup 弹窗 + wav 声音（-Flash 模式：光条 + 声音）
│   ├── flash-glow.ps1           # 全屏左右呼吸光条
│   ├── notify-watcher.ps1       # OpenCode watcher：跟随事件流触发光条 + 声音
│   ├── hook-wrapper.cmd         # popup+声音 hook 入口 (Claude Code)
│   ├── hook-wrapper-flash.cmd   # 光条 hook 入口 (Claude Code)
│   ├── notification.wav         # 默认提示音
│   ├── merge-hooks.js           # 部署时合并 settings.json 的 Node 脚本
│   └── opencode-notifier.js     # OpenCode V2 TUI 插件（部署为 plugins/notifier/tui.js）
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
OpenCode 事件流 ──┬─► notify-watcher.ps1 ──► show-notification.ps1 -Flash ──► 光条 + wav 声音
                  │
                  └─► TUI 插件 (tui.js) ──► OSC 9;4 / OSC 2 ──► 标签环 + 标题标记
```

### popup + 声音的顺序

`show-notification.ps1` 里，声音播放放在 popup 窗口的 `Loaded` 回调中，用 `SoundPlayer.Play()` 异步播放：

1. WPF 加载 XAML → popup 渲染出来
2. `Loaded` 事件触发 → 声音开始播（异步，不阻塞 UI）
3. 5 秒后 popup 自动关闭

`-Flash` 模式不弹窗：先起光条子进程，再用 `PlaySync()` 播完 wav（进程退出会截断异步播放的声音）。

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

OpenCode 的颜色映射在 `src/notify-watcher.ps1` 的 `$rules` 里（完成→绿，需要操作→黄）。

### 改 popup 位置 / 样式

编辑 `src/show-notification.ps1` 里 `Show-Popup` 函数的 XAML。

### 改标签标记

编辑 `src/opencode-notifier.js` 顶部的 `TAB_MARK_WORK` / `TAB_MARK_DONE`。

---

## 故障排查

**Claude Code 没触发**：查 `%TEMP%\hook-triggered.txt`。

**OpenCode 没有光条/声音**：

1. 查 `%TEMP%\claude-notifier.log` —— 正常应有 `watcher: started`，之后每轮出现
   `watcher: Green event` / `Yellow event` 和 `FLASH OK` / `SOUND`。
   若只有 `started` 没有事件，说明 watcher 连上了但事件没被匹配；
   若连 `started` 都没有，watcher 没起来（`Get-CimInstance Win32_Process -Filter "Name='powershell.exe'"` 里找 `notify-watcher`）。
2. 确认服务在跑：`opencode service status`。
3. watcher 的输出重定向在 `%TEMP%\notify-watcher.out.log`。

**OpenCode 标签环/标题不动**：查 `%USERPROFILE%\opencode-notifier-debug.log`，
应有一行 `=== PLUGIN LOADED === isTTY=true`。`isTTY=false` 说明 stdout 被重定向，
插件会故意不写转义序列。改完插件要重启 OpenCode 才会重新加载。

**有记录但没通知**：查 `%TEMP%\claude-notifier.log` —— `SOUND FAIL` / `POPUP FAIL` / `FLASH FAIL` 会告诉你哪一步出错。

**声音听不到但日志正常**：确认 `notification.wav` 是 PCM 格式。
