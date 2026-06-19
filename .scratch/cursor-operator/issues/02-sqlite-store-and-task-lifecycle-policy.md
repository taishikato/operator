Status: ready-for-human

# Local SQLite store and task lifecycle policy

## Parent

.scratch/cursor-operator/PRD.md

## What to build

Add durable local persistence and the core task lifecycle to Cursor Operator. A user should be able to create local task records through the app, see them survive restart, move them through the allowed Ready, Running, Done, and Archived lifecycle, and observe immutability rules for sent or archived work.

This slice should establish the deep persistence and lifecycle modules that later repository registration, send preview, and Cursor runtime slices will use. It should keep the behavior demoable with local-only placeholder repositories or seed data where needed, without contacting Cursor.

## Acceptance criteria

- [x] Cursor Operator stores repositories, tasks, and run attempt metadata in a local SQLite database under the Cursor Operator app data directory.
- [x] Ready, Running, Done, and Archived task states are represented in the domain model and persistence layer.
- [x] Ready tasks are editable.
- [x] Running, Done, and Archived task content is immutable.
- [x] Running tasks can be manually marked Done.
- [x] Ready, Running, and Done tasks can be archived, and archived tasks are hidden from the default board.
- [x] The lifecycle policy prevents hard delete and rerun-after-success behavior at the domain level.
- [x] Tests cover allowed and disallowed lifecycle transitions, immutability, archive behavior, and persistence across store reload.

## Blocked by

- .scratch/cursor-operator/issues/01-app-shell-and-isolated-app-data.md
