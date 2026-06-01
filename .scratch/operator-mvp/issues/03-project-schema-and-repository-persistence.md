Status: ready-for-human
Type: AFK

# Project schema and repository persistence

## Parent

.scratch/operator-mvp/PRD.md

## What to build

Persist Projects as Operator's repository-scoped workspaces. A Project should represent exactly one Git repository, have a globally unique immutable key, keep non-reused Task numbering state, store scheduling/model defaults, and support removal from Operator without deleting any repository files or logs.

## Acceptance criteria

- [x] A Project can be created with repository path, immutable key, display name, repository metadata, defaults, and scheduling settings.
- [x] Project keys are globally unique across active Projects.
- [x] Duplicate repository paths are rejected across active Projects.
- [x] Project task numbers are allocated monotonically and are not reused.
- [x] Removing a Project hides it from active selection and scheduling without deleting repository files, logs, or historical records.
- [x] Tests cover creation, duplicate key rejection, duplicate path rejection, and next-number allocation through the public Project repository interface.

## Blocked by

- .scratch/operator-mvp/issues/02-local-app-data-and-db-bootstrap.md

## Comments

### Implementation result

Implemented Project persistence for Issue #3 in `webapp/`:

- Extended the Drizzle schema source of truth with a `projects` table for immutable Project keys, repository path and metadata, model/reasoning defaults, scheduling settings, run timeout, removal state, and `next_task_number`.
- Added partial unique indexes for active Project keys and active repository paths using `removed_at IS NULL`.
- Added a public Project repository interface for creating Projects, reading active Projects, listing active/schedulable Projects, allocating monotonic Project task numbers, and removing Projects without deleting their historical row.
- Added behavior tests through the public repository interface for creation, duplicate key rejection, duplicate repository path rejection, monotonic task number allocation, and removal from active/scheduled selection.
- Added schema export coverage to confirm the Project table and active uniqueness indexes are emitted from Drizzle Kit SQL export.

Verification:

- `pnpm test` passed 28 tests.
- `pnpm typecheck` passed.
- `pnpm lint` passed with one pre-existing warning in `app/layout.tsx` for an unused `Geist` import.
- `pnpm build` passed.
