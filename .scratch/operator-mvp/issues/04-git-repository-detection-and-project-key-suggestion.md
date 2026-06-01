Status: ready-for-human
Type: AFK

# Git repository detection and Project key suggestion

## Parent

.scratch/operator-mvp/PRD.md

## What to build

Add the repository inspection behavior used by Add Project. Given a local path, Operator should determine whether it is a valid Git repository and return the metadata needed to prefill Project creation. It should also suggest a short Project key from the repository name while preserving the user's ability to edit the key before saving.

## Acceptance criteria

- [x] A valid Git repository path returns repository name, default branch when available, remote URL when available, GitHub slug when available, package-manager hints, and instruction-file presence.
- [x] A non-repository path is rejected with a user-actionable error.
- [x] Project key suggestion normalizes repository names into uppercase alphanumeric keys of the configured length range.
- [x] Key suggestion avoids obvious invalid output for empty, symbolic, or punctuation-heavy names.
- [x] Tests use public repository-detection and key-suggestion interfaces with temporary paths/repositories where practical.

## Blocked by

- .scratch/operator-mvp/issues/02-local-app-data-and-db-bootstrap.md

## Comments

### Implementation result

Implemented Git repository detection and Project key suggestion for Issue #4 in `webapp/`:

- Added a public `detectProjectRepository` interface that resolves the Git repository root, returns the repository name, detects the current/default branch, reads the origin remote URL, extracts GitHub slugs from common GitHub remote URL forms, detects package-manager hints in deterministic order, and reports present instruction files.
- Added a typed `ProjectRepositoryDetectionError` for non-Git paths with a user-actionable `not_git_repository` code and message.
- Added a public `suggestProjectKey` interface that strips symbols, uppercases alphanumeric characters, truncates to the configured maximum length, and falls back to `PROJ` for empty or symbolic names.
- Added behavior tests through public interfaces using temporary repositories and paths.

Verification:

- RED/GREEN TDD cycles were used for GitHub slug extraction and instruction-file detection.
- `pnpm test` passed 39 tests.
- `pnpm typecheck` passed.
- `pnpm lint` passed with one existing warning in `app/layout.tsx` for an unused `Geist` import.
- `pnpm build` passed.
