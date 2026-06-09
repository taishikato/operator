# SQLite Store and Task Lifecycle

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/operator-desktop-mvp/PRD.md`

## What to build

Add durable local persistence with SQLite and GRDB, plus the core Task lifecycle policy. The app should persist repositories, tasks, and run attempts, and enforce the MVP lifecycle rules independently from the UI.

The central behavior is that Tasks start in Ready, can move to Review only through a successful send, can move from Review to Done or Archived manually, and cannot return to Ready after successful send. Trigger failures leave the Task in Ready.

Decision model:

```text
Ready --send accepted--> Review --manual--> Done
Ready --send failed----> Ready + failed badge
Ready --manual archive-> Archived
Review --manual archive-> Archived
Done --manual archive--> Archived

Disallowed:
Review -> Ready
Done -> Ready
Archived -> Ready
successful task -> send again
```

## Acceptance criteria

- [ ] Local data is stored in SQLite through GRDB.
- [ ] Database initialization and migration run on app startup.
- [ ] Repositories, Tasks, and Runs can be persisted and loaded.
- [ ] New Tasks default to Ready.
- [ ] Ready Tasks can be archived.
- [ ] Review Tasks can be moved to Done.
- [ ] Review Tasks can be archived.
- [ ] Done Tasks can be archived.
- [ ] Review, Done, and Archived Tasks cannot move back to Ready.
- [ ] A Task can have at most one successful Run.
- [ ] Failed Run attempts can exist before one successful Run.
- [ ] Review, Done, and Archived Task content is immutable.
- [ ] Hard delete is not exposed.
- [ ] Lifecycle behavior is covered by tests that exercise external state transitions.

## Blocked by

- `01-native-app-shell-and-board.md`
