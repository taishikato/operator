# Runtime Guardrails

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/operator-desktop-mvp/PRD.md`

## What to build

Lock in the MVP responsibility boundaries so future implementation does not drift back into agent-runtime behavior. The app should explicitly avoid Codex completion tracking, result classification, diff inspection, raw log persistence, transcript persistence, PR creation, branch creation, scheduling, automatic cleanup, and rerun behavior.

This issue is mostly tests and small guardrail behavior around the completed MVP flow.

Scope this to the native SwiftUI desktop app. Ignore `webapp/`; it is reference material only.

Operator remains a local Codex trigger/navigation/configuration surface. This issue should preserve those boundaries with tests and small UI/model guardrails only. Do not add new product scope while enforcing the guardrails.

## Acceptance criteria

- [ ] There is no schedule, cron, timezone, missed schedule, trigger queue, or concurrency setting in the MVP UI.
- [ ] There is no Backlog column.
- [ ] There is no Running column.
- [ ] There is no Review to Ready movement.
- [ ] There is no rerun action after a successful send.
- [ ] There is no hard delete action.
- [ ] There is no automatic worktree cleanup.
- [ ] There is no PR creation action.
- [ ] There is no branch creation action during worktree preparation.
- [ ] There is no diff, changed-file count, test result, commit status, or Codex completion status shown in Operator.
- [ ] App-server raw events are not persisted.
- [ ] Codex transcripts are not persisted.
- [ ] Failure storage is limited to short trigger-level errors.
- [ ] Tests assert the forbidden lifecycle transitions remain forbidden.
- [ ] Tests assert successful Tasks cannot be sent again.
- [ ] Tests assert the send flow does not store raw event or transcript content.
- [ ] Implementation branch is published with a non-draft PR after the guardrails are complete.

## Implementation notes

- `06-codex-app-server-trigger.md` and `07-open-in-codex-app.md` are complete and merged.
- `08-settings-and-codex-status.md` is complete in the current issue #8 line of work and should be treated as the base for this guardrail pass.
- Use TDD. Add failing tests for forbidden UI affordances, lifecycle transitions, send/rerun restrictions, no raw event/transcript persistence, and short trigger-level failure storage before production changes.
- Prefer assertions against explicit models/projections/services over brittle UI string scans where practical.
- Worktree preparation must remain detached and must not create branches.
- Operator must not add schedule/concurrency settings, PR actions, hard delete actions, rerun actions after successful send, Codex completion status, diff/test/commit status, transcript storage, raw event storage, or automatic worktree cleanup.
- After implementation, create a non-draft PR with base branch `feature/desktop`.
