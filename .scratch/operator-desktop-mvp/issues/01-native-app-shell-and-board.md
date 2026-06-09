# Native App Shell and Empty Board

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/operator-desktop-mvp/PRD.md`

## What to build

Create the native macOS app shell for Operator Desktop MVP. The app should launch directly into a board view, use a SwiftUI-native layout, target macOS 15 Sequoia or later, and establish the core navigation surfaces for the MVP: mixed-repository board, archived view/filter, and settings entry.

This slice does not need real persistence or Codex integration yet. It should be demoable as a native app showing the Ready, Review, and Done columns with an empty state and placeholder navigation.

## Acceptance criteria

- [ ] The app builds and launches as a native macOS SwiftUI app.
- [ ] The app targets macOS 15 Sequoia or later.
- [ ] The initial screen is the board, not a landing page.
- [ ] The default board shows Ready, Review, and Done columns.
- [ ] The board supports an empty state suitable for "no repositories/tasks yet".
- [ ] There is a visible path to Settings.
- [ ] There is a visible path to Archived tasks, but Archived is not a default board column.
- [ ] The app structure leaves room for a right-side inspector panel in later slices.
- [ ] The implementation does not use Electron, Tauri, or a Next.js desktop shell.

## Blocked by

None - can start immediately
