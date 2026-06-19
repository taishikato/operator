Status: ready-for-human

# MVP guardrails and desktop polish

## Parent

.scratch/cursor-operator/PRD.md

## What to build

Add the final MVP guardrails and desktop polish pass. The app should make setup status clear, expose common actions through toolbar/menu/keyboard affordances, and protect the product boundary decided in the PRD: no local Cursor runtime, no prompt augmentation, no branch ownership, no PR orchestration, no raw logs, no result classification, no automatic Git network operations, and no status polling.

This slice should also smooth the board and settings experience enough that the MVP is coherent as a desktop app.

## Acceptance criteria

- [x] Toolbar, menu, and keyboard paths exist for common board actions where appropriate.
- [x] Repository and Cursor credential setup status are visible enough to diagnose why sending is unavailable.
- [x] The UI clearly states or shows that Cursor Cloud Agent starts from the remote default branch and excludes local-only changes.
- [x] Guardrail tests verify no prompt augmentation is introduced.
- [x] Guardrail tests verify Cursor Operator does not own branch naming, PR creation, raw logs, diffs, commits, test results, or Cursor result classification.
- [x] Guardrail tests verify no automatic fetch, pull, push, merge, or rebase is performed by MVP send flows.
- [x] Guardrail tests verify no Cursor run polling, webhook handling, or Cursor Desktop deep linking is required.
- [x] The final app build and test suite pass for the Cursor Operator package.

## Blocked by

- .scratch/cursor-operator/issues/01-app-shell-and-isolated-app-data.md
- .scratch/cursor-operator/issues/02-sqlite-store-and-task-lifecycle-policy.md
- .scratch/cursor-operator/issues/03-repository-registration-with-github-origin-detection.md
- .scratch/cursor-operator/issues/04-task-creation-and-send-preview.md
- .scratch/cursor-operator/issues/05-cursor-credential-settings-with-keychain-storage.md
- .scratch/cursor-operator/issues/07-send-task-to-cursor-with-fake-runtime.md
- .scratch/cursor-operator/issues/08-real-cursor-cloud-agent-rest-client.md
- .scratch/cursor-operator/issues/09-open-in-cursor-and-manual-completion-flow.md
