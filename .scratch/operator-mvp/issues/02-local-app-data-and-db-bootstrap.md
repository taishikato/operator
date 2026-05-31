Status: ready-for-human
Type: AFK

# Local app data and DB bootstrap

## Parent

.scratch/operator-mvp/PRD.md

## What to build

Create the local storage foundation for Operator. The app should resolve an OS-appropriate app data directory, create required subdirectories, place the local database and run-log area outside managed Git repositories, and initialize the database only when it is missing or uninitialized. Existing databases should not be automatically migrated except through the explicit apply command path.

## Acceptance criteria

- [x] Operator resolves a deterministic app data directory for the current OS.
- [x] Operator creates database and run-log directories when needed.
- [x] Run logs are addressed by relative log keys rather than absolute paths.
- [x] Local DB initialization only applies schema on first initialization.
- [x] Existing local DBs require an explicit apply command path for schema updates.
- [x] Behavior is covered by tests through public app-data/bootstrap interfaces.

## Blocked by

- .scratch/operator-mvp/issues/01-db-compatibility-spike.md

## Comments

### Implementation result

Implemented the Issue #2 local storage foundation in `webapp/`:

- Added public app-data helpers to resolve deterministic OS app data paths, create the required directories, and convert relative run log keys such as `runs/{runId}.jsonl` into safe filesystem paths.
- Added the local database bootstrap boundary. Missing or empty DB files run first-initialization schema apply and write an `operator_metadata` initialization marker. Initialized DBs do not auto-apply schema at startup. Non-empty DBs without the marker return `requires_explicit_apply`.
- Added the explicit `applyLocalDatabaseSchema` path for existing schema updates.
- Added the initial Drizzle bootstrap schema and wired the default path as Drizzle Kit SQL export into Atlas declarative apply.

Verification:

- `pnpm test` passed 18 tests.
- `pnpm typecheck` passed.
- `pnpm lint` passed with one pre-existing warning in `app/layout.tsx` for an unused `Geist` import.
- `pnpm build` passed.
