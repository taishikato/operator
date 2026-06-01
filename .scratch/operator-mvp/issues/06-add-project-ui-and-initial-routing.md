Status: ready-for-human
Type: AFK

# Add Project UI and initial routing

## Parent

.scratch/operator-mvp/PRD.md

## What to build

Build the first user-facing setup path. When no active Project exists, the root screen should present Add Project. The user can enter a repository path, trigger detection, review the detected metadata and suggested Project key, save the Project, and land on that Project's Kanban placeholder. If a Project already exists, the root route should take the user to the last active Project.

## Acceptance criteria

- [x] Root route shows Add Project when no active Project exists.
- [x] Root route redirects or navigates to the last active Project when one exists.
- [x] Add Project UI supports path input, detect, metadata preview, editable key before save, and save.
- [x] macOS Browse is represented through the local backend path; unsupported platforms fall back to manual path input.
- [x] Successful Project creation navigates to the new Project's route.
- [x] Validation errors are shown in the UI without losing entered form data.
- [x] UI behavior is covered by tests where practical through user-observable flows.

## Blocked by

- .scratch/operator-mvp/issues/05-add-project-api-and-validation.md

## Comments

### Implementation result

Implemented Add Project UI and initial routing for Issue #6 in `webapp/`:

- Replaced the root template with a dynamic setup route that shows Add Project when there are no active Projects and redirects to the most recently created active Project route when one exists.
- Added an interactive Add Project form with repository path input, macOS backend Browse affordance, Detect, metadata preview, editable Project key, display name, Save, and validation error display that preserves entered form data.
- Added `POST /api/projects/browse` as the local backend folder picker boundary. macOS uses `osascript` to choose a folder; unsupported platforms return a structured fallback error so manual path input remains usable.
- Added `/projects/[projectKey]` as the initial Kanban placeholder route reached after successful Project creation.
- Added focused behavior tests for root Project route selection, Add Project form state transitions, validation error preservation, and browse fallback behavior.

Verification:

- RED/GREEN TDD cycles were used for initial route selection, Add Project UI state, browse fallback behavior, and browse route exposure.
- `node --experimental-strip-types --test lib/projects/project-routing.test.ts` passed.
- `node --experimental-strip-types --test lib/projects/add-project-ui-state.test.ts` passed.
- `node --experimental-strip-types --test lib/projects/browse-project-path.test.ts` passed.
- `pnpm test` passed 65 tests.
- `pnpm typecheck` passed.
- `pnpm lint` passed with one pre-existing warning in `app/layout.tsx` for an unused `Geist` import.
- `pnpm build` passed with the known Turbopack warning about dynamic filesystem tracing through the route import path.
- Verified manually with `@Browser`: root showed Add Project, Detect populated metadata and suggested key for a temporary Git repository, Save navigated to `/projects/OPERAT`, and the Project Kanban placeholder rendered.
