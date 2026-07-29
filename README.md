# Codex Tower

Codex Tower is a local macOS-first Codex plugin for keeping track of multiple conversations. It tracks lifecycle metadata in a shared local data directory and plays a sound when a task needs attention or is explicitly marked complete.

## What v0.1 tracks

- Per-session status: `running`, `waiting_for_you`, `awaiting_review`, `completed`, and `closed`.
- A short task title from the latest submitted prompt (limited to 100 characters).
- Plan progress emitted by `update_plan` and subagent lifecycle counts.
- No full transcripts or tool output.
- Existing local threads can be imported as neutral `history` cards with no inferred completion state.
- Opening an `awaiting_review` task marks it as `reviewed` immediately; later lifecycle events replace that local view state.

## Sound behavior

- `Basso`: Codex asks for approval.
- `Glass`: a turn stops and is awaiting review.
- `Hero`: the `mark_task_complete` tool explicitly marks a task complete.

On macOS, sounds use the built-in `/usr/bin/afplay`; other platforms record statuses without sound. Use the `update_settings` tool to mute or unmute notifications.

## Menu-bar app

`menu-bar-app` is a native macOS SwiftUI app. It shows a small status-bar icon; click it to open a grouped task dashboard and mute notifications. It reads the same JSON files as the plugin from `~/Library/Application Support/Codex Tower` (or `CODEX_TOWER_DATA_DIR` when set).

Build it with:

```zsh
cd /Users/haruki/plugins/codex-tower/menu-bar-app
./build-app.sh
open "dist/Codex Tower.app"
```

The app stays out of the Dock (`LSUIElement`) and is unsigned for local use. Use the macOS login-item settings to launch it automatically after you decide to keep it.

## Install and trust

Install from the personal marketplace, then review and trust the plugin's hooks before using it. Start a new Codex task after installation so its lifecycle hooks and MCP tools are discovered.

## v0.1 boundary

The plugin only observes local Codex sessions where its hooks are enabled. The menu-bar app polls the local metadata once a second and does not read or upload conversation transcripts.
