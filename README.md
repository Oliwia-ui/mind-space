# Mind Space

Mind Space is a local-first macOS task app that turns scattered thoughts into a calm plan. Its default spatial view represents saved tasks and projects as floating glass objects; **MAKE IT MAKE SENSE** transforms the same data into a structured task list.

> Development is in progress on `feat/mind-space-app`. The scaffold builds, while task persistence, Obsidian logging, and the finished interface are being implemented.

## Stack

- Tauri 2 desktop shell
- React 19 + TypeScript + Vite
- Rust backend
- SQLite local persistence
- Vitest + Testing Library and Rust tests

## Development setup

Requirements:

- macOS 13 or later
- Node.js 22+
- Rust stable (`rustup`)
- Xcode Command Line Tools

```bash
npm ci
npm run tauri dev
```

## Checks

```bash
npm run test
npm run build
cargo test --manifest-path src-tauri/Cargo.toml
```

Run every check with:

```bash
npm run check
```

## Privacy and storage

Mind Space is fully offline. It does not include accounts, telemetry, ads, cloud sync, or remote APIs. The packaged app stores its SQLite database in the app data directory assigned by macOS. The selected Obsidian vault path is stored as a local preference. Database files, environment files, and vault contents are ignored by Git.

## Obsidian integration

Settings will provide a native folder picker for choosing an existing Obsidian vault. Task events append to:

```text
Productivity Log/
  Tasks/
    YYYY-MM-DD.md
  Focus/             # reserved for the separate timer app
```

Task actions succeed even if vault logging fails. Failed entries remain queued locally, the interface shows that the vault needs attention, and the user can retry.

## Future timer connection

Every task receives a stable `task_<uuid>` identifier. The model reserves `estimatedFocusMinutes` and `externalSessionReferences`, allowing the separate Pomodoro app to attach completed focus sessions without changing task identity or reshaping existing records.

## Documentation

- [`docs/PRD.md`](docs/PRD.md) — product and technical design
- [`docs/reference/`](docs/reference/) — visual direction artifacts and design decisions

## Known limitations

The first release is macOS-first and single-user. It intentionally excludes cloud sync, collaboration, recurring tasks, notifications, calendar integration, analytics, and an embedded timer.
