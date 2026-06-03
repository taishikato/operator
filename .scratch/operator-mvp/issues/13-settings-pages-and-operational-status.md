Status: ready-for-human
Type: AFK

# Settings pages and operational status

## Parent

.scratch/operator-mvp/PRD.md

## What to build

Provide dedicated settings pages for Project configuration and App operational status. Project settings should control repository-facing defaults and schedule behavior. App settings should show local operational state such as app data directory, Cursor API key configured/missing, version, and theme controls.

## Acceptance criteria

- [x] Settings are available at the Project settings route with Project and App tabs.
- [x] Project settings can update default model, default reasoning level, schedule enabled, daily time, timezone, scheduled run limit, and run timeout.
- [x] App settings show app data directory, Cursor API key configured/missing, Operator version, and theme controls.
- [x] App-level default model/reasoning editing is not included in the MVP.
- [x] Settings use explicit Save behavior where changes can affect execution.
- [x] In-app toasts report successful saves and validation failures.
- [x] Tests cover settings persistence through public API/UI behavior where practical.

## Blocked by

- .scratch/operator-mvp/issues/06-add-project-ui-and-initial-routing.md
- .scratch/operator-mvp/issues/12-project-scheduler-and-batch-execution.md

## Implementation result

- Added `/projects/[projectKey]/settings` with Project and App tabs.
- Added Project settings persistence through `PATCH /api/projects/[projectKey]/settings` for defaults, schedule settings, and run timeout.
- Added App operational status for app data directory, Cursor API key configured/missing, Operator version, and theme controls.
- Added Sonner `Toaster` wiring and save success / validation failure toasts.
- Added Settings navigation from the Project board header.
- Intentionally excluded App-level default model/reasoning editing, PR creation UI, and CLI start/db apply polish.

## Verification

- `pnpm test` passed.
- `pnpm typecheck` passed.
- `pnpm lint` passed.
- `pnpm build` passed with an existing Turbopack NFT import-trace warning from `next.config.ts` through `detect-project-repository.ts`.
