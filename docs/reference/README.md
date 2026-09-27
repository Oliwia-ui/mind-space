# Mind Space visual references

These artifacts are original design references for implementing Mind Space. They deliberately treat the product as an **Explore surface first** and an **Operate surface second**: the opening view supports spatial browsing and reflection; the structured view supports direct task work without becoming a generic dashboard.

## Artifacts

### 1. [`mind-space-direction-board.svg`](mind-space-direction-board.svg)

A composition and visual-language board for the opening Mind Space.

It helped decide:

- the asymmetric spatial field rather than a card grid;
- the semantic object vocabulary: task cards, project cubes, and idea spheres;
- the burnt-orange organising action as the single visual gravity well;
- the compact bottom capture control as a persistent but peripheral affordance;
- the graphite/navy base, off-white type, and muted blue/purple/green metadata colors;
- where smoky glass is earned (floating objects crossing the spatial canvas) and where it is not;
- the motion posture: slow, low-amplitude drift with generous negative space.

### 2. [`structured-task-view-wireframe.svg`](structured-task-view-wireframe.svg)

A high-fidelity layout reference for the structured task interface after transformation.

It helped decide:

- a narrow translucent navigation rail instead of a dashboard shell;
- one dominant task-list column with calm row-level hierarchy;
- explicit separation between the short Today commitment and uncommitted later work;
- a contextual inspector that appears only while adding or editing;
- consistent access to completion without adding permanent controls to every edge;
- restrained project color as metadata, with orange reserved for selection and commit actions;
- the deliberate exclusion of charts, streaks, productivity scores, and arbitrary metrics.

### 3. [`transformation-motion-storyboard.svg`](transformation-motion-storyboard.svg)

A six-frame motion storyboard for **MAKE IT MAKE SENSE**, covering the full 900 ms transition and its reduced-motion alternative.

It helped decide:

- the phase sequence: commit signal, convergence, axis reveal, row resolution, and focus handoff;
- that drift stops before objects begin travelling, making the action feel intentional;
- that each task object remains visually traceable into its corresponding list row;
- that navigation appears behind moving objects rather than replacing the canvas abruptly;
- that glass treatment falls away only after objects land in the list;
- the exact timing handoffs and easing posture;
- a 180 ms reduced-motion crossfade/direct reflow with orbit, trails, and pulse removed;
- the core invariant that transformation never mutates task data or stable IDs.

## Shared implementation principles

- Preserve the same underlying records across spatial and structured views.
- Prefer hierarchy, position, and whitespace over decorative containers.
- Keep blur restrained and tied to real depth; do not apply glass to every surface.
- Use orange only for the primary organising action, current selection, and committed action.
- Keep motion explanatory and interruptible, never theatrical or blocking.
- Do not turn either view into a feature-card grid or analytics dashboard.

All SVGs are self-contained and use no external images, fonts, scripts, or brand assets.
