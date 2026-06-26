#!/usr/bin/env node
/**
 * merge-hooks.js — merge Claude Code notification hooks into settings.json
 *
 * Called by deploy.ps1.  Uses Node.js built-in JSON to avoid PowerShell
 * ConvertFrom-Json issues with complex settings.json files.
 *
 * Usage:
 *   node merge-hooks.js install  <settingsPath> <scriptPath>
 *   node merge-hooks.js uninstall <settingsPath>
 */

const fs = require('fs');
const path = require('path');

const [,, action, settingsPath, scriptPath] = process.argv;

if (!settingsPath) {
    console.error('Usage: node merge-hooks.js <install|uninstall> <settingsPath> [scriptPath]');
    process.exit(1);
}

// ── Read settings ──────────────────────────────────────────────────────────
let settings;
try {
    const raw = fs.readFileSync(settingsPath, 'utf8');
    settings = JSON.parse(raw);
} catch (err) {
    console.error(`ERROR: Cannot read/parse ${settingsPath}: ${err.message}`);
    process.exit(1);
}

// ═══════════════════════════════════════════════════════════════════════════
// INSTALL
// ═══════════════════════════════════════════════════════════════════════════
if (action === 'install') {
    if (!scriptPath) {
        console.error('ERROR: install requires <scriptPath> argument');
        process.exit(1);
    }

    // Wrapper path: same dir as the notification script, but hook-wrapper.cmd
    const wrapperPath = require('path').dirname(scriptPath) + '\\hook-wrapper.cmd';

    // Use exec form: command=executable, args=arguments array.
    // This spawns the process directly without a shell — no quoting issues AT ALL.
    const hookDefs = [
        {
            event: 'Stop',
            matcher: '',
            command: 'cmd',
            args: ['/c', wrapperPath, 'Task completed - Claude waiting'],
            timeout: 5,
            desc: 'Stop (task completion)',
        },
        {
            event: 'SubagentStop',
            matcher: '',
            command: 'cmd',
            args: ['/c', wrapperPath, 'Subagent task completed'],
            timeout: 5,
            desc: 'SubagentStop (subagent completion)',
        },
        {
            event: 'PreToolUse',
            matcher: 'AskUserQuestion',
            command: 'cmd',
            args: ['/c', wrapperPath, 'Claude needs your input'],
            timeout: 5,
            desc: 'PreToolUse / AskUserQuestion (user question)',
        },
        {
            event: 'Elicitation',
            matcher: '',
            command: 'cmd',
            args: ['/c', wrapperPath, 'Claude needs your response - Elicitation dialog'],
            timeout: 5,
            desc: 'Elicitation (auto mode / form / dialog)',
        },
        {
            event: 'PermissionRequest',
            matcher: '',
            command: 'cmd',
            args: ['/c', wrapperPath, 'Claude needs permission approval'],
            timeout: 5,
            desc: 'PermissionRequest (tool permission needed)',
        },
    ];

    // Ensure hooks object exists
    if (!settings.hooks) {
        settings.hooks = {};
    }

    let added = 0;
    let skipped = 0;

    for (const def of hookDefs) {
        // Ensure event array exists
        if (!Array.isArray(settings.hooks[def.event])) {
            settings.hooks[def.event] = [];
        }

        // Check for duplicate (match both command and args)
        const exists = settings.hooks[def.event].some(
            (entry) => entry.hooks && entry.hooks[0] &&
                entry.hooks[0].command === def.command &&
                JSON.stringify(entry.hooks[0].args) === JSON.stringify(def.args || [])
        );

        if (exists) {
            console.log(`  [skip] ${def.desc} — already configured`);
            skipped++;
            continue;
        }

        // Build hook entry (exec form: command + args, no shell)
        const hookObj = {
            type: 'command',
            command: def.command,
            timeout: def.timeout,
        };
        if (def.args) {
            hookObj.args = def.args;
        }

        const entry = {
            hooks: [hookObj],
        };

        if (def.matcher) {
            entry.matcher = def.matcher;
        }

        // Add to start of array for Stop event (without matcher it doesn't matter)
        if (def.matcher) {
            // For matched hooks, add after unmatched ones if any
            settings.hooks[def.event].push(entry);
        } else {
            // For unmatched hooks, prepend so they're checked first
            settings.hooks[def.event].unshift(entry);
        }

        console.log(`  [add] ${def.desc}`);
        added++;
    }

    // Write back
    const output = JSON.stringify(settings, null, 2) + '\n';
    fs.writeFileSync(settingsPath, output, 'utf8');

    console.log('');
    console.log(JSON.stringify({ added, skipped }));
}

// ═══════════════════════════════════════════════════════════════════════════
// UNINSTALL
// ═══════════════════════════════════════════════════════════════════════════
else if (action === 'uninstall') {
    if (!settings.hooks) {
        console.log('  No hooks configured — nothing to remove.');
        console.log(JSON.stringify({ removed: 0 }));
        process.exit(0);
    }

    const events = ['Stop', 'SubagentStop', 'PreToolUse'];
    let removed = 0;

    for (const event of events) {
        if (!Array.isArray(settings.hooks[event])) continue;

        const before = settings.hooks[event].length;
        settings.hooks[event] = settings.hooks[event].filter((entry) => {
            if (!entry.hooks || !entry.hooks[0]) return true; // keep unknown entries
            const cmd = entry.hooks[0].command || '';
            return !cmd.includes('show-notification.ps1') && !cmd.includes('hook-wrapper.cmd');
        });
        const after = settings.hooks[event].length;

        if (after === 0) {
            delete settings.hooks[event];
        }

        if (before !== after) {
            removed += before - after;
        }
    }

    // Remove empty hooks object
    if (Object.keys(settings.hooks).length === 0) {
        delete settings.hooks;
    }

    // Write back
    const output = JSON.stringify(settings, null, 2) + '\n';
    fs.writeFileSync(settingsPath, output, 'utf8');

    if (removed > 0) {
        console.log(`  Hooks removed (${removed} entries).`);
    } else {
        console.log('  No matching notification hooks found.');
    }

    console.log(JSON.stringify({ removed }));
}

else {
    console.error(`Unknown action: ${action}. Use "install" or "uninstall".`);
    process.exit(1);
}
