Status: ready-for-agent

# Task creation and send preview

## Parent

.scratch/cursor-operator/PRD.md

## What to build

Allow users to create and edit Ready tasks for registered repositories, then review the exact send context before a task is handed to Cursor. The task form should stay intentionally small: title, repository, prompt, and auto-create PR. The preview should show repository URL, starting ref, fixed model, auto-create PR setting, and the prompt exactly as written.

This slice should not send anything to Cursor yet. It should make the eventual send contract visible and testable, including that `composer-2.5` is fixed and prompt text is not secretly augmented by Operator.

## Acceptance criteria

- [ ] Users can create Ready tasks with title, repository, prompt, and auto-create PR setting.
- [ ] Users can edit Ready tasks before sending.
- [ ] Task prompt is stored and previewed exactly as written.
- [ ] Auto-create PR is a task-level toggle that defaults off.
- [ ] The send preview displays repository URL, starting ref, fixed `composer-2.5` model, auto-create PR value, and prompt text.
- [ ] No model selector, reasoning selector, acceptance criteria field, labels, priority, due date, or dependency UI is introduced.
- [ ] Tests cover task creation, Ready task editing, auto-create PR defaulting, fixed model display, and prompt-as-written preview behavior.

## Blocked by

- .scratch/cursor-operator/issues/02-sqlite-store-and-task-lifecycle-policy.md
- .scratch/cursor-operator/issues/03-repository-registration-with-github-origin-detection.md
