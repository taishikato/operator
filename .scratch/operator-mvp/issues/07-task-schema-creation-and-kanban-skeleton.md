Status: ready-for-agent
Type: AFK

# Task schema, creation, and Kanban skeleton

## Parent

.scratch/operator-mvp/PRD.md

## What to build

Introduce Tasks and the first Kanban surface. Users should be able to create a Task with title, body, acceptance criteria, and default execution settings, then see it in the Project board across the MVP columns. The slice should establish Task IDs, Project-scoped numbering, statuses, basic ordering, and a minimal Task drawer.

## Acceptance criteria

- [x] A Task can be created for a Project with title, markdown body, and markdown acceptance criteria.
- [x] Each Task receives a stable display ID from the Project key and Project-scoped number.
- [x] Task numbers are not reused after archive/removal behavior.
- [x] Kanban displays Backlog, Ready, Running, Review, Done, and Blocked columns.
- [x] Newly created Tasks appear in the expected initial column.
- [x] Opening a Task by display ID in the URL shows a minimal Task drawer.
- [x] Tests cover Task creation and display ID behavior through public interfaces.

## Blocked by

- .scratch/operator-mvp/issues/06-add-project-ui-and-initial-routing.md

## Implementation result

Completed in branch `operator-mvp-issue-07-task-schema-kanban`.

- Added the Task persistence schema and export coverage for Project-scoped numbers, stable display IDs, markdown body, markdown acceptance criteria, status, ordering position, and archive metadata.
- Added Task repository behavior for creation, active listing, display ID lookup, and archival without number reuse.
- Added `GET` and `POST` Task API handlers under `/api/projects/[projectKey]/tasks`.
- Replaced the Project placeholder with the first Kanban skeleton, Task creation form, Backlog placement for new Tasks, and a minimal URL-addressable Task drawer.
- Kept drag-and-drop, Task editing/preview, run orchestration, scheduler, raw logs, and PR creation out of scope.

Verification:

- `node --experimental-strip-types --test lib/db/schema-export.test.ts lib/tasks/task-repository.test.ts lib/tasks/task-api.test.ts lib/tasks/kanban-view.test.ts`
- `pnpm test`
- `pnpm typecheck`
- `pnpm lint`
- `pnpm build` passed with the existing Turbopack NFT warning on the Project detection import trace.
- Browser verification on `http://127.0.0.1:3927/projects/OP?task=OP-1` confirmed `OP-1` appears in Backlog and opens the drawer by display ID.
