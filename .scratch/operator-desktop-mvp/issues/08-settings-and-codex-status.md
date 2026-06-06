# Settings and Codex Status

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/operator-desktop-mvp/PRD.md`

## What to build

Build the MVP Settings surface. Settings should let the user manage repositories, view/edit repository default branches, inspect or override the Codex binary path, see Codex readiness/status, view the Operator app data path, and see basic About information.

Operator should not own Codex login. If Codex is missing or unauthenticated, Settings and send failures should guide the user toward Codex CLI/App setup rather than collecting credentials.

Scope this to the native SwiftUI desktop app. Ignore `webapp/`; it is reference material only.

Operator remains a local Codex trigger/navigation surface. This issue should improve configuration and readiness visibility only. Do not add scheduling, Codex completion tracking, transcript reads, diff inspection, PR automation inside the app, merge detection, or credential collection.

## Acceptance criteria

- [ ] Settings includes repository management.
- [ ] Repository settings allow viewing and editing default branch.
- [ ] Settings shows the detected Codex binary path.
- [ ] Settings allows overriding the Codex binary path with an absolute path.
- [ ] Settings shows Codex status such as not checked, ready, not found, or not authenticated/unavailable.
- [ ] Send uses the configured Codex binary path.
- [ ] Settings shows the Operator app data path.
- [ ] Settings includes basic About information.
- [ ] Operator does not collect or persist Codex credentials.
- [ ] Missing Codex binary is surfaced as a clear status and send failure.
- [ ] Codex authentication failure is surfaced as a clear status and send failure.
- [ ] Tests cover binary-path selection and status classification where practical.
- [ ] Implementation branch is published with a non-draft PR after the feature is complete.

## Implementation notes

- `01-native-app-shell-and-board.md` and `03-repository-registration.md` are complete on `feature/desktop`.
- `07-open-in-codex-app.md` is complete and merged into `feature/desktop` via PR #24.
- Use TDD. Add failing tests for binary path selection, override validation, status classification, and send using the configured binary before production changes.
- Prefer dependency injection for Codex binary/status checks so tests never require a real Codex install, authentication, or app-server process.
- Codex binary override must be an absolute path.
- Settings may guide the user to install/login through Codex CLI/App, but must not collect, store, or transmit credentials.
- After implementation, create a non-draft PR with base branch `feature/desktop`.
