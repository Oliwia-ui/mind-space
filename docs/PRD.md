# Mind Space — Product and Design Document

## Product name and purpose

**Mind Space** is a local-first macOS task app that helps one person move from unstructured capture to an understandable next-action plan. It treats unfinished thoughts as a calm visual space first, then lets the user transform that space into a conventional, usable task list.

## Intended user and problem

The intended user captures tasks, ideas, coursework, and projects quickly, but does not always organise them at capture time. Existing task dashboards can make that input feel like administrative work. Mind Space preserves fast capture while creating a deliberate moment in which confusion becomes clarity.

## Core features

- Create, view, edit, complete, reopen, and safely delete tasks.
- Inbox by default, deliberately selected Today list, projects, Done, and Logbook.
- Stable task IDs for future focus-session links.
- SQLite persistence in the macOS app data directory.
- Native Obsidian vault selection and append-only Markdown event history.
- Clear recoverable state when vault logging fails.

## Custom features

- Data-driven Mind Space with task cards, project cubes, and idea spheres.
- Subtle levitation and orbital movement with a reduced-motion mode.
- **MAKE IT MAKE SENSE** transforms spatial objects into the structured view in approximately 900 ms without changing task data.

## Non-goals

Mind Space does not include accounts, cloud sync, collaboration, notifications, recurring tasks, calendar sync, complex analytics, AI planning, gamification, or Pomodoro controls.

## Main user flow

1. Open the app into Mind Space.
2. Capture a thought; it becomes an Inbox task unless a project is selected.
3. Inspect or edit a floating real-data object.
4. Select **MAKE IT MAKE SENSE**.
5. Objects converge and resolve into the structured task interface.
6. Choose a short Today list, work through tasks, and complete them.
7. Mind Space persists each action locally and appends task events to the configured Obsidian vault.

## Screen layout

### Mind Space

A near-black navy canvas contains faint stars and orbital guides. Objects are distributed with generous space around a warm burnt-orange central action. A compact capture control and quiet settings access remain visible.

### Structured view

A narrow translucent sidebar contains Today, Inbox, Projects, Done, Logbook, and Settings. The main column shows a focused task list. A details panel appears only when adding or editing, avoiding a permanent dashboard feel.

## Framework choice

Tauri 2 with React and TypeScript provides a small native desktop shell, a familiar typed UI model, native dialog access, and a Rust boundary for durable local storage and filesystem writes. This is lighter than Electron while keeping the interface approachable for a student developer.

## Local storage choice

SQLite is the source of truth. It supports transactional task actions, projects, preferences, pending vault events, and future migrations. The database is local to the app data directory and works without network access.

## Obsidian vault structure

```text
Productivity Log/
  Tasks/
    YYYY-MM-DD.md
  Focus/
    YYYY-MM-DD.md
```

Task history is append-only. Each entry records local date, local time, IANA timezone, event type, task ID, title, project, status, and changed fields where relevant. `Focus/` is reserved for the separate timer app.

## Usability decisions

- New tasks default to Inbox to keep capture fast.
- Today is an explicit selection rather than an automatic due-date dump.
- Trash is recoverable and task deletion is never silent.
- Completion remains available on every task row.
- Burnt orange is reserved for the primary organising action and selected states.
- Motion stays slow and low-amplitude; reduced motion shortens transitions and removes drift.
- Vault failure never rolls back a valid task action.

## Alternative considered but not chosen

A conventional generic task dashboard and a combined Pomodoro-and-task screen were considered. Both were rejected because they would make the product less personal, more cluttered, and too close to existing task apps. The timer is a separate product, while Mind Space is built around visual capture and the transition from ambiguity to order.

## Testable acceptance criteria

- A created task remains after app relaunch.
- A task can be viewed, edited, safely deleted, completed, and reopened.
- Projects can be created and assigned to tasks.
- New tasks enter Inbox by default.
- A task can be added to and removed from Today.
- Mind Space objects derive from saved task and project records.
- Selecting an object opens the corresponding item by stable ID.
- **MAKE IT MAKE SENSE** reaches the structured view without mutating task data.
- Reduced-motion mode removes nonessential drift and shortens the transformation.
- Create, edit, complete, reopen, and delete events append correct Markdown to the chosen vault.
- Existing Markdown records are never overwritten.
- Vault errors are visible, retryable, and do not destroy task data.
- The app works with network access disabled.
- A clean clone can install dependencies, test, build, and launch using documented commands.
