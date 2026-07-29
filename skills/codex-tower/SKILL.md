---
name: codex-tower
description: Use Codex Tower to inspect local multi-chat task status, change notification settings, and explicitly mark verified tasks complete.
---

# Codex Tower

Use this skill when the user asks about their Codex task statuses, requests notification changes, or asks to mark a Codex task complete.

## Status semantics

- `running`: a user prompt is being handled.
- `waiting_for_you`: Codex requested an approval.
- `awaiting_review`: the latest turn stopped; this is **not** proof that the task is done.
- `completed`: only set with `mark_task_complete` after the work has been verified or the user explicitly confirms completion.
- `closed`: the session ended.

## Workflow

1. Call `list_tasks` to inspect the local dashboard data.
2. Use `sync_existing_tasks` to import historical local Codex threads. Imported threads use the neutral `history` status until live hooks update them.
3. Never infer `completed` from `awaiting_review` alone.
4. When a task is genuinely complete, call `mark_task_complete` with its `session_id` and an optional brief non-sensitive summary. This plays the completion sound once.
5. Use `update_settings` to mute or unmute sounds on the user's request.

Codex Tower intentionally stores metadata only: session id, title, project directory, statuses, timestamps, plan counts, and subagent identifiers. Do not put conversation contents or secrets in completion summaries.
