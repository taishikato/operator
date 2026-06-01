Status: ready-for-human
Type: AFK

# Add Project API and validation

## Parent

.scratch/operator-mvp/PRD.md

## What to build

Expose the Add Project behavior through explicit local API endpoints. The API should validate input, detect repository metadata, enforce Project key and repository path rules, create the Project, and return enough information for the UI to route to the new Project.

## Acceptance criteria

- [x] The API can detect repository metadata for a supplied path without creating a Project.
- [x] The API can create a Project from valid repository path, key, and detected/default settings.
- [x] Invalid paths, invalid keys, duplicate keys, and duplicate repository paths return structured validation errors.
- [x] The API does not require Cursor credentials to add a Project.
- [x] The API does not write anything inside the managed Git repository.
- [x] Tests cover API-observable behavior rather than internal helper calls.

## Blocked by

- .scratch/operator-mvp/issues/03-project-schema-and-repository-persistence.md
- .scratch/operator-mvp/issues/04-git-repository-detection-and-project-key-suggestion.md

## Comments

### Implementation result

Implemented Add Project API and validation for Issue #5 in `webapp/`:

- Added `POST /api/projects/detect` to validate a supplied repository path, return detected repository metadata, and provide a suggested Project key without creating a Project row.
- Added `POST /api/projects` to validate Project creation input, detect repository metadata, apply default Project settings, persist the Project, and return routing-ready data for `/projects/{key}`.
- Added structured API errors for non-Git paths, invalid Project keys, duplicate active Project keys, and duplicate active repository paths.
- Kept Add Project independent of Cursor credentials and verified detect/create do not dirty the managed repository.
- Added API-observable tests through the public request handler boundary plus route-handler endpoint presence checks.
- Added `serverExternalPackages` for `@tursodatabase/database` so the new Route Handlers build successfully under Next/Turbopack.

Verification:

- RED/GREEN TDD cycles were used for detect, create, non-Git path validation, invalid key validation, duplicate key validation, duplicate repository path validation, and Route Handler presence.
- `node --experimental-strip-types --test lib/projects/add-project-api.test.ts` passed 9 tests.
- `pnpm test` passed 49 tests.
- `pnpm typecheck` passed.
- `pnpm lint` passed with one pre-existing warning in `app/layout.tsx` for an unused `Geist` import.
- `pnpm build` passed with one Turbopack warning about dynamic filesystem tracing through the route import path.
