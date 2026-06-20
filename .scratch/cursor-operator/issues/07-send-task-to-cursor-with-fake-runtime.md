Status: ready-for-human

# Send task to Cursor with fake runtime

## Parent

.scratch/cursor-operator/PRD.md

## What to build

Implement the end-to-end send flow using a fake Cursor runtime client. A user should be able to send a Ready task, see a run attempt recorded, see success move the task to Running with a saved fake Cursor reference, and see failure leave the task in Ready with a sanitized error and retry capability.

This slice should prove the orchestration, persistence, UI states, retry behavior, and one-successful-send guardrail before real Cursor networking is added.

## Acceptance criteria

- [x] Sending a Ready task creates a run attempt with trigger-level metadata.
- [x] The runtime request includes prompt text, repository URL, starting ref, fixed `composer-2.5` model, and auto-create PR as fields rather than hidden prompt text.
- [x] A fake successful runtime response moves the task to Running and stores a Cursor agent id and open URL.
- [x] A fake failed runtime response leaves the task Ready and stores a short sanitized error.
- [x] Failed Ready tasks can be edited and retried, creating a new run attempt.
- [x] A task with one successful send cannot be sent again.
- [x] Raw event streams, transcripts, full HTTP bodies, secrets, diffs, commits, and PR status are not stored.
- [x] Tests cover success, failure, retry, sanitization, missing credential blocked behavior, and one-successful-send guardrail.

## Blocked by

- .scratch/cursor-operator/issues/02-sqlite-store-and-task-lifecycle-policy.md
- .scratch/cursor-operator/issues/03-repository-registration-with-github-origin-detection.md
- .scratch/cursor-operator/issues/04-task-creation-and-send-preview.md
- .scratch/cursor-operator/issues/05-cursor-credential-settings-with-keychain-storage.md
