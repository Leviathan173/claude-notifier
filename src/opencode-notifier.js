/**
 * opencode-notifier.js — OpenCode plugin for Windows desktop notifications.
 *
 * Listens to OpenCode events and triggers the same PowerShell notification
 * scripts used by the Claude Code notifier: WPF popup + breathing glow + wav sound.
 *
 * Installation:
 *   1. Run deploy-opencode.ps1 to copy this file and the PS scripts to OpenCode dirs.
 *   2. Restart OpenCode — the plugin loads automatically from ~/.config/opencode/plugins/.
 *
 * Event mapping:
 *   session.idle        -> "Task completed" (green glow + popup + sound)
 *   session.error        -> "Error occurred" (red glow + popup + sound)
 *   permission.asked     -> "Needs your input" (yellow glow + popup + sound)
 *   session.status (subagent_done) -> "Subagent completed" (green glow + popup + sound)
 */

export const OpencodeNotifier = async ({ project, client, $, directory, worktree }) => {
    const scriptsDir = "$env:USERPROFILE\\.config\\opencode\\scripts";

    async function notify(title, message, color) {
        const popupScript = `${scriptsDir}\\show-notification.ps1`;
        const flashScript = `${scriptsDir}\\flash-glow.ps1`;
        try {
            await client.app.log({
                body: { service: "opencode-notifier", level: "info", message: `notify: ${title} - ${message}` },
            });
            // Fire popup + sound and glow in parallel
            await Promise.all([
                $`powershell -STA -NoProfile -ExecutionPolicy Bypass -File ${popupScript} -Title ${title} -Message ${message} -Sound Default`.quiet(),
                $`powershell -STA -NoProfile -ExecutionPolicy Bypass -File ${flashScript} -Color ${color}`.quiet(),
            ]);
        } catch {
            // Notifications are best-effort; never break the session.
        }
    }

    return {
        event: async ({ event }) => {
            switch (event.type) {
                case "session.idle":
                    await notify("OpenCode", "Task completed - waiting", "#00C853");
                    break;

                case "session.error":
                    await notify("OpenCode", "Error occurred", "#F44336");
                    break;

                case "permission.asked":
                    await notify("OpenCode", "Needs your input", "#FFD600");
                    break;

                case "session.status":
                    if (event.properties?.status === "subagent_done") {
                        await notify("OpenCode", "Subagent completed", "#00C853");
                    }
                    break;
            }
        },
    };
};
