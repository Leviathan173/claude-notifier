# Claude Code Windows Toast Notifier

Windows 右下角 toast 通知系统，用于 Claude Code 的任务完成和权限确认提示。

## 功能

| 触发场景 | 通知内容 | 提示音 |
|---------|---------|--------|
| Claude 完成对话 | "Task completed — Claude is waiting for you" | Default（轻提示） |
| 子代理任务完成 | "Subagent task completed" | Default（轻提示） |
| Claude 需要你的输入 | "Claude needs your response" | IM（消息提示） |

## 快速开始

### 一键部署

```powershell
.\deploy.ps1
```

### 一键卸载

```powershell
.\deploy.ps1 -Uninstall
```

### 手动测试

```powershell
powershell -File "$env:USERPROFILE\.claude\scripts\show-notification.ps1" -Title "Test" -Message "Hello from Claude Code" -Sound "Default"
```

## 要求

- Windows 10 / 11
- PowerShell 5.1+
- Claude Code（已安装并配置 `~/.claude/settings.json`）

**零外部依赖** — 使用 Windows 内置 WinRT Toast API。

## 文件结构

```
claude-notifier/
├── src/
│   └── show-notification.ps1   # 核心通知脚本
├── deploy.ps1                   # 一键部署/卸载脚本
├── .gitignore
└── README.md
```

## 工作原理

1. `show-notification.ps1` 使用 Windows 原生 WinRT `ToastNotificationManager` API 发送 toast。
2. 首次运行时自动注册 AppUserModelID（在开始菜单创建快捷方式）。
3. 如果 toast API 不可用，回退到控制台 `Beep` 声音。
4. `deploy.ps1` 将脚本复制到 `~/.claude/scripts/` 并将 hooks 配置合并到 `settings.json`。

## 自定义声音

修改 `deploy.ps1` 中 hook 命令的 `-Sound` 参数：

| 别名 | 效果 |
|------|------|
| `Default` | 系统默认通知音 |
| `IM` | 即时消息提示音 |
| `Mail` | 邮件提示音 |
| `Reminder` | 提醒提示音 |
| `SMS` | 短信提示音 |
| `Alarm` | 闹钟音 |
| `Silent` | 静音 |
