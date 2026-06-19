Status: ready-for-agent

# Cursor Operator app shell and isolated app data

## Parent

.scratch/cursor-operator/PRD.md

## What to build

Create the initial Cursor Operator native macOS app as its own Swift package and app, separate from Codex Operator. The slice should boot into a simple desktop board window with Ready, Running, and Done columns, expose Archived as a separate hidden-from-default surface or placeholder, provide a native Settings scene, and establish an isolated app data location that cannot collide with Codex Operator.

This is a tracer bullet for the app container: the app should build, run, show the core desktop structure, and prove that Cursor Operator has its own identity and local data root. It should not implement real task persistence or Cursor runtime behavior yet.

## Acceptance criteria

- [ ] A separate Cursor Operator Swift package/app exists and builds independently of Codex Operator.
- [ ] Launching the app opens a native SwiftUI desktop window directly to the task board surface.
- [ ] The board visibly contains Ready, Running, and Done columns, with Archived not shown as an active default column.
- [ ] A native Settings scene is reachable from the app.
- [ ] The app resolves and displays or logs an isolated Cursor Operator app data directory distinct from Codex Operator.
- [ ] The app has a basic test/build command path documented for future implementation slices.

## Blocked by

None - can start immediately
