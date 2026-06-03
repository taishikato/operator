Status: ready-for-human
Type: AFK

# Manual draft PR creation via gh

## Parent

.scratch/operator-mvp/PRD.md

## What to build

Add the optional manual PR path for Tasks in Review. The user should be able to confirm branch, remote, commit, title, body, and draft status before Operator pushes the branch and asks `gh` to create a draft PR. Operator should store the resulting PR URL and keep the Task in Review.

## Acceptance criteria

- [x] Create PR action is available for Review Tasks with a committed branch and no existing PR URL.
- [x] Confirmation UI shows remote, branch, commit SHA, PR title/body, and draft status.
- [x] The action pushes the branch only after confirmation.
- [x] The action creates a draft PR through local `gh` authentication.
- [x] The Task remains in Review after PR creation.
- [x] The Task displays a PR badge/link after successful creation.
- [x] PR creation failure records a useful error without moving the Task to Done.
- [x] Tests use a command adapter fake rather than a real GitHub push.

## Blocked by

- .scratch/operator-mvp/issues/10-cursor-sdk-run-orchestration-tracer.md
