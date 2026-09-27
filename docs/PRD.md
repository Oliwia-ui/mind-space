# Mind Space — Product and Technical Design

## Product and purpose

**Mind Space** is a native, offline macOS To Do app that turns unfinished thoughts into a calm plan. It opens as a spatial reflection surface and transforms the same real task data into a structured working view.

## Intended user and problem

The app is for one person who captures coursework, projects, ideas, and small obligations faster than they can organise them. Generic task dashboards add administrative pressure. Mind Space keeps capture lightweight and creates a deliberate transition from ambiguity to order.

## Core features

- Create, view, edit, complete, reopen, and safely trash tasks.
- Inbox by default, an explicitly chosen Today list, projects, Done, Logbook, and Settings.
- Stable task identifiers for future Pomodoro session links.
- Versioned SQLite persistence stored locally on the Mac.
- Native macOS Obsidian vault selection with append-only Markdown history.
- Visible retryable state when vault logging fails without rolling back task actions.

## Custom features

- Data-driven Mind Space where cards represent tasks, cubes represent projects, and spheres represent ideas.
- Pool-like rearrangement where any existing task, project, or idea can be dragged as the pusher; there is no separate pusher tool or pusher orb.
- Soft capped collisions, restrained contact halos, gradual inertial settling, safe canvas boundaries, locally persisted positions, and a Reset Layout action.
- A 700–1200 ms **MAKE IT MAKE SENSE** transition that preserves data while changing its presentation from spatial objects to task rows and project groups.

## Non-goals

Mind Space does not include accounts, cloud sync, collaboration, notifications, recurring tasks, calendars, AI planning, analytics, gamification, or Pomodoro controls.

## Main user flow

1. Open Mind Space and see real unfinished work represented spatially.
2. Capture a thought, which becomes an Inbox task unless a project is chosen.
3. Select an object to inspect or edit the associated real item.
4. Press **MAKE IT MAKE SENSE**.
5. Objects converge and resolve into the structured task interface.
6. Choose a short Today list, organise projects, and complete tasks.
7. SQLite persists each action and the logging service appends the corresponding event to the configured Obsidian vault.

## Framework decision

The application uses **Swift and SwiftUI**. This satisfies the native Apple requirement, provides macOS accessibility and animation APIs directly, and lets the domain and view models be reused by a future iPhone SwiftUI target. AppKit is used only where macOS-specific behavior is required, such as selecting a vault folder.

## Local storage decision

**SQLite** is the source of truth for tasks, projects, preferences, and future pending log events. SwiftData was evaluated first, but its macro implementation is unavailable in the installed Xcode Command Line Tools, preventing the required clean-clone build and test verification. SQLite is built into macOS, fully offline, supports explicit versioned migrations and deterministic reopen tests, and keeps persistence independent of the UI. The typed repository and domain models live in `MindSpaceCore` so a future iPhone SwiftUI target can reuse them without exposing SQL to views.

## Obsidian vault structure

```text
Productivity Log/
  Tasks/
    YYYY-MM-DD.md
  Focus/
    YYYY-MM-DD.md
```

Mind Space writes only to `Tasks/`. `Focus/` is reserved for the separate timer app. Events are appended and include local date, time, IANA timezone, event type, status, task ID, title, project, and changed fields when relevant. Existing entries are never replaced.

## Screen layout

### Mind Space

A near-black navy canvas contains faint stars and restrained orbital guides. Saved task cards, project cubes, and idea spheres occupy generous negative space around the warm burnt-orange transformation control. The transformation control is not a physics object and never acts as a pusher. Existing thought objects can be dragged into one another to create slow, soft movement; positions are saved after the objects settle.

### Structured view

A native SwiftUI `NavigationSplitView` contains Today, Inbox, Projects, Done, Logbook, and Settings. The main column shows readable task rows and calm empty states. Add/edit work appears in a focused sheet or inspector instead of a permanent dashboard of panels.

## Usability decisions

- New tasks enter Inbox to make capture immediate.
- Today is deliberately chosen rather than automatically filled from due dates.
- Delete moves a task to recoverable Trash and offers Undo.
- Completion is present on every task row and completed tasks can be reopened.
- Burnt orange is reserved for the primary transformation and selected actions.
- Motion explains continuity but never delays access; system Reduce Motion and the in-app preference shorten or remove it.
- Physics remain deliberately non-game-like: speed is capped, boundary contact does not bounce, collisions are soft, and movement decays to rest.
- Reset Layout clears only saved spatial positions and restores the calm automatic arrangement without changing tasks or projects.
- Vault failure cannot destroy or reject a valid task action.
- Stable string IDs remain independent of database row identifiers so the timer app can link sessions safely.

## Alternative considered and rejected

A generic dashboard and a combined task/Pomodoro screen were considered. They were rejected because they would be more cluttered, less personal, too similar to existing task apps, and would blur the boundary with the separate timer product. A separate pusher tool or decorative pusher orb was also rejected because the physical interaction must come from moving the user's own editable thought objects.

## Testable acceptance criteria

- Creating a task persists it across a new model container/application launch.
- Tasks can be edited, completed, reopened, and moved to recoverable Trash.
- Projects can be created and assigned to tasks.
- A task without a selected project defaults to Inbox.
- Tasks can be added to and removed from Today.
- Mind Space objects derive from actual saved tasks and projects.
- Selecting an object opens the corresponding item by stable ID.
- Dragging a real task, project, or idea into another real object gently pushes the contacted object in the direction of travel.
- Thought movement remains speed-limited, settles without chaotic bouncing, and cannot leave the safe canvas bounds.
- Contact produces a subtle temporary halo, and settled positions survive application relaunch.
- Reset Layout restores the automatic arrangement without mutating task or project data.
- **MAKE IT MAKE SENSE** reaches the structured view without mutating task data.
- Reduced motion shortens or skips the transformation while direct manipulation remains available.
- Create, edit, complete, reopen, and delete events append correct Markdown.
- Existing Markdown history remains intact after every write.
- Vault errors remain visible and retryable while task state stays saved.
- The packaged app works with network access unavailable.
- A clean clone can run tests, build a signed local `.app`, and launch using documented commands.
