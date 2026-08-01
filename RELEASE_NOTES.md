# Codex Tower v0.1.4

## A faster task center

- Fixed the `ready` lifecycle state so newly started tasks always appear in the dashboard.
- Added clickable native macOS notifications for tasks that need attention or have completed.
- Added card-level **Done** and one-hour **Later** actions.
- Added a **Done** filter and automatic archiving of completed tasks after 24 hours.
- Added automatic English and Simplified Chinese interface localization.

---

# Codex Tower v0.1.3

## Complete tasks from Codex

- Send `task complete` as a standalone message in a Codex task to mark it completed without leaving the conversation.
- Chinese users can send `验收完成` instead.
- The task dashboard updates immediately and plays the configured completion sound once.

---

# Codex Tower v0.1.2

## Easier installation

- Added a drag-to-Applications macOS DMG installer.
- Added a GitHub-backed Codex marketplace, so users can install the plugin from the Codex Plugins page after one marketplace command.

---

# Codex Tower v0.1.1

## Updated

- Dashboard now opens on **Active** tasks, keeping live work ahead of imported history.
- Added a dedicated **History** filter for browsing imported local tasks.
- Replaced the menu-bar symbol with a clearer twin-tower silhouette.
- Plays native macOS sounds when tasks need attention or are explicitly marked complete.

---

# Codex Tower v0.1.0

Codex Tower v0.1.0 is the first local macOS release.

## Included

- Native macOS menu-bar dashboard with recent-first task timeline.
- Direct task-card navigation to the matching Codex conversation.
- All, Attention, and Active task filters.
- Historical local-thread sync without saving transcript content.
- Local lifecycle tracking, macOS notification sounds, mute control, and explicit completion state.

## Privacy

The app stores only local task metadata. It does not upload task data or persist conversation transcripts.

## Requirements

- macOS 13 or later.
- Codex Tower lifecycle hooks must be reviewed and trusted in Codex before real-time tracking and sounds run.
