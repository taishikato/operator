# Operator MVP Design Notes

This document captures the MVP decisions for Operator. It intentionally stands apart from the existing generated agent docs.

## Product Shape

- Operator is an open-source, local-first Kanban control plane for scheduled Cursor SDK agent runs.
- Operator's own Kanban board is the task source of truth.
- The MVP is a localhost web app first, with a future desktop wrapper path.
- The app is source-checkout-first for distribution.
- The first implementation lives in `webapp/`.
- MVP prerequisites:
  - Node.js and pnpm
  - `CURSOR_API_KEY` in the process environment for agent runs
  - `gh` CLI authenticated locally for optional draft PR creation
  - Atlas CLI if Atlas declarative apply remains the selected schema apply tool after the DB spike
- The default localhost URL is `http://127.0.0.1:3927`.

## Core Decisions

- Project = one Git repository.
- Duplicate repository paths are not allowed.
- Project keys are globally unique across all active Projects.
- Tasks are managed in six columns: Backlog, Ready, Running, Review, Done, Blocked.
- Ready is the only scheduled execution column.
- Ready column order is execution order.
- Task dependencies, human assignees, labels, due dates, and structured checklists are out of scope.
- Model and Cursor SDK reasoning level are Project defaults with Task overrides.
- No AgentProfile abstraction in the MVP.

## Runtime

- Cursor SDK local runtime is the primary MVP runtime.
- Cursor credentials come from `CURSOR_API_KEY`.
- Operator does not persist Cursor secrets.
- Cursor CLI and Cursor Cloud runtime are future adapters.
- The agent is responsible for implementation, checks, and English commits.
- Operator is responsible for task orchestration, preflight checks, branch setup, log capture, and Git outcome observation.

## Git Flow

- Run preflight checks:
  - Cursor API key present
  - repo path exists
  - repo path is a Git repo
  - working tree is clean
  - default branch exists
  - Task branch can be created or checked out
  - model is configured
  - Cursor SDK runtime can initialize
- Branch name: `operator/{project-key-lower}-{task-number}-{slug}`.
- The branch name is generated once on first run and stored on the Task. Reruns reuse the stored branch name instead of recomputing from the current title.
- The slug is title-derived at first branch creation only; Task branch identity is the Project key plus Task number.
- Reruns reuse the same Task branch.
- Operator does not automatically pull, merge, or rebase.
- Success requires HEAD to change during the run and the working tree to be clean according to `git status --porcelain --untracked-files=all`, excluding ignored files.
- Failures move the Task to Blocked with a reason.

## Run Result Classification

| Commit delta | Working tree | Task result |
| --- | --- | --- |
| yes | clean | Review |
| no | dirty | Blocked: `worktree_dirty_no_commit` |
| no | clean | Blocked: `no_commit_created` |
| yes | dirty | Blocked: `dirty_after_commit` |

Other blocked reasons include `dirty_worktree`, `interrupted`, `agent_error`, `canceled`, `timeout`, `git_error`, and `pr_create_failed`.

- `dirty_worktree` means the repository was dirty before the agent started.
- `worktree_dirty_no_commit` means the agent finished without a new commit and left uncommitted changes behind.
- `no_commit_created` intentionally treats "nothing changed" as Blocked in the MVP; a human can move the Task to Done if that was correct.

## Scheduling

- Schedule is Project-level, daily, structured UI.
- Schedule is disabled by default.
- Project timezone defaults to browser/system timezone.
- The scheduler only runs while Operator is running.
- Missed schedules do not catch up automatically.
- Each Project stores the last scheduled local date that fired, evaluated in the Project timezone, to prevent duplicate daily runs.
- Timezone evaluation must use a timezone-aware helper rather than naive UTC/local Date arithmetic.
- Each scheduled tick runs up to `scheduledRunLimit`, defaulting to 1.
- One active run per Project.
- Different Projects may run concurrently.
- Batch execution stops after the first failure within that Project. Other Projects may continue independently.

## Data And Storage

- DB and logs live in the OS app data directory, not in managed repos.
- Local DB uses `@tursodatabase/database` with Drizzle beta.
- Drizzle schema is the schema source of truth.
- Atlas declarative apply manages schema sync.
- Before relying on Atlas in implementation, run a compatibility spike for `@tursodatabase/database` + Drizzle beta + Atlas declarative apply. If Atlas cannot safely introspect/apply this DB, revisit the schema apply tool before building the DB layer.
- Local mode runs schema apply only on first DB initialization.
- Existing local DBs and future cloud DBs require explicit `operator db apply`.
- Internal IDs use ULID.
- Projects have immutable short keys.
- Tasks have non-reused Project-scoped numbers.
- Timestamps are ISO UTC strings.
- Raw logs are redacted JSONL with Cursor SDK events plus Operator events.
- Raw logs are retained indefinitely in the MVP.

## UI

- Existing template stack: Next.js, React, Tailwind 4, shadcn/base-nova, lucide, next-themes.
- Add Sonner via shadcn for in-app toasts.
- Use TanStack Query with Route Handlers.
- Use `@dnd-kit` for Kanban drag-and-drop.
- Use Zod for shared validation.
- State management is TanStack Query plus React local state only.
- Initial screen:
  - no Project: Add Project
  - existing Project: last Project Kanban
- Routes:
  - `/`
  - `/projects/[projectKey]`
  - `/projects/[projectKey]?task=OP-24`
  - `/projects/[projectKey]/settings`
  - `/runs/[runId]`
- Task detail uses a right drawer.
- Raw log viewer uses a dedicated page.
- Settings is a dedicated page with Project and App tabs.
- App settings are mostly read-only status plus theme.
- Theme supports system theme plus manual toggle.

## Add Project

- Add Project uses path input plus macOS native Browse button.
- Non-macOS fallback is manual path entry.
- The macOS Browse button is implemented server-side from the local backend, using the native folder picker through `osascript`. Browser-only directory pickers are not sufficient because Operator needs an absolute repository path for Git and Cursor SDK work.
- Detection includes:
  - Git repo validity
  - default branch
  - remote URL
  - GitHub slug if available
  - package manager hints
  - instruction file presence
- Project key is suggested from repo name, editable before save, immutable after save.

## PR Flow

- Draft PR creation is optional and manual.
- Use `gh` CLI and existing local GitHub auth.
- Confirm before push:
  - remote
  - branch
  - commit SHA
  - PR title/body
  - draft status
- Create PR with `gh pr create --draft`.
- Task remains in Review after PR creation.

## First Implementation Chunk

1. Create this design doc and the PRD in `.scratch/operator-mvp/PRD.md`.
2. Add required dependencies for DB/schema validation/query foundation as needed.
3. Run the DB compatibility spike for Turso local, Drizzle beta, and Atlas declarative apply.
4. Create app data directory helper.
5. Create initial Drizzle schema for Projects, Tasks, and Runs.
6. Wire the selected schema apply path for first local initialization and explicit apply.
7. Implement Add Project API and UI.
8. Implement Git repo detection and Project key suggestion.
9. Route `/` to Add Project or the last Project's Kanban placeholder.
10. Run typecheck/build for the chunk.

## Process Model And Recovery

- `operator start` owns a single local app process that starts the production Next.js server plus an in-process job runner and scheduler.
- Route Handlers should enqueue run work and return; long Cursor agent work runs in the local job runner, not inside the lifetime of an HTTP request.
- Development mode may use `pnpm dev`, but scheduler/job-runner behavior should avoid accidental duplicate workers during hot reload.
- On startup, Operator reconciles stale Running Tasks/Runs from the previous process. Any run still marked Running is moved to Blocked with reason `interrupted`.
- The MVP does not attempt to resume interrupted Cursor SDK sessions automatically.

## Future Work

- Cursor Cloud runtime adapter.
- Cursor CLI debug/fallback adapter.
- Desktop wrapper.
- Turso Cloud or sync mode.
- GitHub issue import.
- Linear import.
- Task dependencies.
- Global concurrency cap.
- Raw log retention controls.
- OS notifications.
- Archived Task and removed Project restore views.
