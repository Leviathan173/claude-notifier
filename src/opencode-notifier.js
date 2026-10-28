/**
 * opencode-notifier.js — OpenCode V2 TUI plugin.
 *
 * Drives the Windows Terminal tab progress ring and the tab title mark for the
 * active session.
 *
 * The desktop flash + sound are NOT here: OpenCode V2 plugins run with a stubbed
 * child_process (spawn returns a fake pid and exit 0 without starting anything),
 * so a plugin cannot launch PowerShell. `notify-watcher.ps1` does that instead,
 * outside of OpenCode, by following the server event stream.
 */

import fs from "fs";
import os from "os";
import path from "path";
import { Plugin } from "@opencode/plugin/tui";

const LOG_FILE = path.join(os.homedir(), "opencode-notifier-debug.log");

// Marks prefixed to the session name in the tab title. Edit to taste.
const TAB_MARK_WORK = "⏳";
const TAB_MARK_DONE = "✅";

function log(msg) {
    try {
        fs.appendFileSync(LOG_FILE, `[${new Date().toISOString()}] ${msg}\n`);
    } catch {}
}

export default Plugin.define({
    id: "desktop-notifier",
    setup(context) {
        const running = new Set();
        let title = "";

        // Only the process owning the WT conpty can write OSC to it, and that is
        // this one (the TUI). A redirected stdout is not a tty — leave it alone.
        function write(seq) {
            if (!process.stdout.isTTY) return;
            try { fs.writeSync(1, seq); } catch (e) { log(`WT WRITE FAIL: ${e}`); }
        }

        // opencode titles the tab "OC | <session name>"; prefix it with our state.
        function applyTitle() {
            if (!title) return; // unknown name — don't clobber opencode's own title
            const mark = running.size ? TAB_MARK_WORK : TAB_MARK_DONE;
            const name = title.length > 40 ? title.slice(0, 37) + "…" : title;
            write(`\x1b]2;${mark} OC | ${name}\x07`);
        }

        // Windows Terminal tab progress ring (OSC 9;4): 3 = indeterminate spinner.
        function ring() {
            write(running.size ? "\x1b]9;4;3\x07" : "\x1b]9;4;0\x07");
        }

        log("=== PLUGIN LOADED === isTTY=" + process.stdout.isTTY);
        ring(); // drop a stale ring from the previous session

        // One execution per turn: started → (renamed) → succeeded/failed/interrupted.
        // Subagent sessions emit their own executions; keeping the ring up while a
        // subagent runs is the behaviour we want, so they are not filtered out.
        const stop = context.data.listen(({ details }) => {
            const data = details?.data;
            if (!data) return;
            switch (details.type) {
                case "session.renamed":
                    if (data.title) {
                        title = data.title.replace(/[\x00-\x1f\x7f]/g, "");
                        applyTitle();
                    }
                    return;
                case "session.execution.started":
                    running.add(data.sessionID);
                    ring();
                    applyTitle();
                    return;
                case "session.execution.succeeded":
                case "session.execution.failed":
                case "session.execution.interrupted":
                    running.delete(data.sessionID);
                    ring();
                    applyTitle();
                    return;
            }
        });

        return () => stop();
    },
});
