Status: ready-for-agent
Type: AFK

# Kanban drag-and-drop ordering

## Parent

.scratch/operator-mvp/PRD.md

## What to build

Make the Kanban board directly control execution order. Users should be able to drag Tasks between columns and reorder Tasks within a column. Ready column order must persist and become the order used by scheduled and manual Ready batch execution.

## Acceptance criteria

- [x] Tasks can be reordered within a column and the order persists after refresh.
- [x] Tasks can be moved between allowed columns.
- [x] Manual movement into Running is not allowed because Running is system-controlled.
- [x] Moving into Ready applies the same Task content validation as other Ready transitions.
- [x] Ready column order can be read by run selection logic.
- [x] Failed optimistic updates roll back or recover clearly.
- [x] Tests cover ordering persistence through the public board/update interface.

## Blocked by

- .scratch/operator-mvp/issues/08-task-editing-markdown-preview-and-ready-validation.md

## Implementation result

- Added a public Task board PATCH API and route for persisted Kanban column ordering.
- Added repository board updates that persist per-column positions, reject manual movement into Running, and reuse Ready validation from Issue #8.
- Added `listReadyTasksForRunSelection` so future run selection logic can read Ready Tasks in persisted execution order without implementing runner orchestration.
- Added a dnd-kit Kanban board with optimistic updates, rollback to the last server-backed board on failed saves, and disabled manual dragging for Running Tasks.
- Added focused tests for public board ordering persistence, Running rejection, Ready validation, Ready run-selection order, and optimistic rollback state.
- Verified with `pnpm test`, `pnpm typecheck`, `pnpm lint`, `pnpm build`, and local Browser inspection.
