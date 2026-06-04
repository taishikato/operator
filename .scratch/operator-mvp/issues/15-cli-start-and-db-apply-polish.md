Status: ready-for-human
Type: AFK

# CLI start and db apply polish

## Parent

.scratch/operator-mvp/PRD.md

## What to build

Polish the local product entrypoints. The source-checkout MVP should expose a production-oriented `operator start` command and an explicit `operator db apply` command. Startup should own the local app process, fixed localhost port, app data setup, scheduler/job runner startup, and interrupted run reconciliation.

## Acceptance criteria

- [x] `operator start` starts the production app on `127.0.0.1:3927` by default.
- [x] Startup fails clearly if the default port is already in use.
- [x] `operator start --open` opens the browser, while default startup only prints the URL.
- [x] Startup performs app data setup and first local DB initialization.
- [x] Startup launches scheduler and in-process job runner exactly once.
- [x] Startup reconciles stale Running work to Blocked with `interrupted`.
- [x] `operator db apply` performs the explicit schema apply path for existing local databases.
- [x] Development flow remains separate from production startup.
- [x] Tests or scripted checks cover CLI-observable behavior where practical.

## Blocked by

- .scratch/operator-mvp/issues/02-local-app-data-and-db-bootstrap.md
- .scratch/operator-mvp/issues/12-project-scheduler-and-batch-execution.md
