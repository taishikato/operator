Status: ready-for-agent
Type: AFK

# Task editing, markdown preview, and Ready validation

## Parent

.scratch/operator-mvp/PRD.md

## What to build

Make Task instructions safe to edit before agent execution. The Task drawer should support explicit Save and Discard for title, markdown body, acceptance criteria, model override, and reasoning override. Moving a Task into Ready should validate Task content but should not require environment readiness.

## Acceptance criteria

- [x] Task body and acceptance criteria can be edited with explicit Save and Discard.
- [x] Markdown preview can be toggled for body and acceptance criteria.
- [x] Unsaved edits do not affect scheduled or manual run input.
- [x] Moving a Task into Ready requires title and at least one of body or acceptance criteria.
- [x] Moving a Task into Ready does not require Cursor API key or other run-time environment checks.
- [x] Validation errors are visible and do not corrupt the Task's prior saved content.
- [x] Tests cover Save/Discard and Ready validation as observable behavior.

## Blocked by

- .scratch/operator-mvp/issues/07-task-schema-creation-and-kanban-skeleton.md

## Implementation result

- Added Task repository update and status transition behavior, including Ready validation that checks only saved Task title/body/acceptance content.
- Added public Task PATCH API and route for instruction edits and status updates.
- Added Task drawer editing with explicit Save/Discard, markdown preview toggles, model/reasoning overrides, visible validation errors, and Ready movement.
- Added focused tests for repository updates, Ready validation, API behavior without `CURSOR_API_KEY`, and drawer edit state.
- Browser-verified drawer preview, discard, save, and Ready movement through the local app.
