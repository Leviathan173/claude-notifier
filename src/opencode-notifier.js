/**
 * opencode-notifier.js — OpenCode plugin for Windows desktop notifications.
 */

import os from "os";
import path from "path";
import fs from "fs";

const LOG_FILE = path.join(os.homedir(), "opencode-notifier-debug.log");
const scriptsDir = path.join(os.homedir(), ".config", "opencode", "scripts");

function log(msg) {
    const ts = new Date().toISOString();
    fs.appendFileSync(LOG_FILE, `[${ts}] ${msg}\n`);
}

function runPs(script, args) {
    return new Promise((resolve, reject) => {
        const fullArgs = ["-STA", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, ...args];
        const proc = Bun.spawn(["powershell", ...fullArgs], {
            stdout: "pipe",
            stderr: "pipe",
        });
        proc.exited.then(async (code) => {
            const stderr = await new Response(proc.stderr).text();
            if (code === 0) {
                resolve();
            } else {
                reject(new Error(`exit=${code} ${stderr}`));
            }
        });
    });
}

export const OpencodeNotifier = async ({ project, client, $, directory, worktree }) => {
    log("=== PLUGIN LOADED ===");
    let lastNotifiedId = null;

    return {
        event: async ({ event }) => {
            log(`EVENT: type=${event.type}`);

            // When assistant message completes (finish=stop), show notification
            if (event.type === "message.updated") {
                const info = event.properties?.info;
                if (info?.role === "assistant" && info?.finish === "stop") {
                    // Deduplicate: skip if we already notified for this message
                    if (lastNotifiedId === info.id) return;
                    lastNotifiedId = info.id;
                    log(`NOTIFY: assistant message completed (id=${info.id})`);
                    try {
                        const popupScript = path.join(scriptsDir, "show-notification.ps1");
                        const flashScript = path.join(scriptsDir, "flash-glow.ps1");
                        await Promise.all([
                            runPs(popupScript, [
                                "-Title", "OpenCode",
                                "-Message", "Response completed",
                                "-Sound", "Default"
                            ]),
                            runPs(flashScript, ["-Color", "#00C853"]),
                        ]);
                        log("NOTIFY: success");
                    } catch (e) {
                        log(`NOTIFY ERROR: ${e}`);
                    }
                }
            }
        },
    };
};
