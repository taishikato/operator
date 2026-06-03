Status: ready-for-human
Type: AFK

# Cursor SDK run orchestration tracer

## Parent

.scratch/operator-mvp/PRD.md

## What to build

Build the first end-to-end Run Now path for a single Task. The slice should prove that Operator can preflight a Task, create or reuse its Task branch, wrap the prompt, start the Cursor SDK local runtime through a testable adapter seam, observe Git before and after the run, and classify the Task outcome into Review or Blocked.

## Acceptance criteria

- [x] Run Now is available for Backlog, Ready, Blocked, and Review Tasks, and unavailable for Running and Done.
- [x] Run preflight checks required environment, repository, branch, and model conditions before agent work begins.
- [x] Dirty working tree before run blocks the Task without launching the agent.
- [x] The Task branch is generated once from Project key, Task number, and initial title slug, then stored and reused.
- [x] The agent prompt includes Task details, acceptance criteria, current-branch constraints, checks instruction, English commit instruction, and no-push instruction.
- [x] The Cursor runtime is accessed through an adapter seam that can be faked in tests.
- [x] HEAD delta and working tree state classify results into Review or the documented Blocked reasons.
- [x] Startup reconciliation can mark stale Running work as Blocked with `interrupted`.
- [x] Tests cover run classification and branch reuse through public orchestration interfaces without requiring a real Cursor run.

## Blocked by

- .scratch/operator-mvp/issues/08-task-editing-markdown-preview-and-ready-validation.md

## Implementation result

Implemented the single-Task Run Now slice in `webapp/`.

- Added Task branch persistence, blocked reasons, and a `runs` metadata table.
- Added a run orchestrator with Git and Cursor adapter seams, branch reuse, prompt building, dirty-worktree preflight blocking, post-run classification, and stale Running reconciliation.
- Added a real Cursor SDK adapter behind the seam using `@cursor/sdk`; automated tests use fake adapters and do not require `CURSOR_API_KEY` or real Cursor runs.
- Added the Task Run Now API route and Kanban Run Now icon buttons for Backlog, Ready, Blocked, and Review only.
- Intentionally did not implement raw JSONL viewing, scheduler/batch execution, or draft PR creation.

Verification completed:

- `pnpm test`
- `pnpm typecheck`
- `pnpm lint`
- `pnpm build` (passes with an existing Turbopack NFT trace warning from the project detect route)
