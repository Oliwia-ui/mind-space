# Mind Space

Mind Space is a native, offline macOS To Do app for turning unfinished thoughts into a calm, structured plan.

This repository is built in **Swift and SwiftUI**, with native SQLite persistence in the reusable `MindSpaceCore` module. The previous Tauri draft PR was closed and will not be merged.

## Current foundation

- Native SwiftUI application target
- Shared `MindSpaceCore` module for future iPhone reuse
- SQLite-backed task, project, Today, Trash, and preferences repository
- Stable `task_<UUID>` identifiers and future focus-session reference fields
- Swift Package Manager build and Swift Testing suite
- Scripted `.app` bundle generation and ad-hoc code-sign verification
- GitHub Actions native build checks

## Local requirements

- macOS 14 or later
- Swift 6 toolchain
- Xcode Command Line Tools for SwiftPM builds
- Full Xcode for Xcode UI-test execution and App Store-style project workflows

## Build and test

```bash
./scripts/test.sh
./scripts/build-app.sh
open "dist/Mind Space.app"
```

## Local data

`MindSpaceCore` stores tasks, projects, Today membership, recoverable Trash state, preferences, and vault bookmark data in a versioned SQLite database. SQLite was selected instead of SwiftData because this repository must build and test from a clean clone using the installed Xcode Command Line Tools, which do not provide the SwiftData macro implementation. The explicit repository boundary remains native, offline, typed, and reusable by a future iPhone SwiftUI target.

The app target will place `MindSpace.store` in its Application Support directory. Tests use isolated in-memory or temporary on-disk databases and never access a real Obsidian vault.

## Obsidian vault activity log

Mind Space can write an append-only task history to an Obsidian vault you select yourself.

1. Press **MAKE IT MAKE SENSE** to open the structured view.
2. Open **Settings** in the sidebar.
3. Under **Obsidian Vault**, choose **Choose Vault…**.
4. Select the root folder of your existing Obsidian vault.
5. Create, edit, complete, reopen, or move a task to Trash.

Mind Space appends records to:

```text
Productivity Log/
  Tasks/
    YYYY-MM-DD.md
```

It never replaces previous entries. Each record contains the local date, time, timezone, event type, status, stable task ID, title, project where relevant, and changed values where relevant. If the vault cannot be written, the task action remains saved locally and the pending event can be retried from Settings.

Example:

```md
## 2026-09-27

- 14:32:18 Europe/Brussels | task_completed
  - id: task_abc123
  - title: “Plan assignment report”
  - status: completed
```
