Status: ready-for-human
Type: AFK

# Project scheduler and batch execution

## Parent

.scratch/operator-mvp/PRD.md

## What to build

Add Project-level daily scheduling and Ready batch execution. The scheduler should run only while Operator is running, should not catch up missed schedules, should avoid duplicate daily fires in a Project timezone, and should process Ready Tasks in persisted Ready order up to the Project run limit.

## Acceptance criteria

- [x] Project schedule settings support enabled/disabled, daily time, timezone, and scheduled run limit.
- [x] Schedules are disabled by default.
- [x] A Project stores the last scheduled local date that fired to prevent duplicate daily runs.
- [x] Missed schedules do not run automatically on app startup.
- [x] Scheduled runs select Ready Tasks by persisted Ready order up to the Project limit.
- [x] One Project cannot run more than one active Task at a time.
- [x] Different Projects may run concurrently.
- [x] A failed, canceled, or timed-out Task stops the batch for that Project.
- [x] Manual Run Ready Tasks defaults to the Project run limit and can run a confirmed custom count.
- [x] Tests cover timezone-aware fire selection, no-catch-up behavior, run limit behavior, and per-Project batch stopping.

## Blocked by

- .scratch/operator-mvp/issues/10-cursor-sdk-run-orchestration-tracer.md

## Implementation result

Implemented Project daily scheduling and Ready batch execution primitives:

- Added `projects.last_scheduled_local_date` and Project repository methods for schedule updates and marking fired Project-local dates.
- Added timezone-aware scheduler selection and a tick entrypoint that skips startup catch-up, prevents duplicate local-date fires, and dispatches due Projects with their scheduled run limit.
- Added Ready batch execution in persisted Ready order, with module-level per-Project concurrency, concurrent execution for different Projects, and stop-on-first blocked/failed result behavior.
- Added manual Ready batch API at `/api/projects/[projectKey]/tasks/run-ready` and a Ready column control that confirms count with the Project run limit as the default.

Verification:

- `pnpm test` passed.
- `pnpm typecheck` passed.
- `pnpm lint` passed.
- `pnpm build` passed with the existing Turbopack NFT warning for `next.config.ts` import tracing through the Project detection route.
