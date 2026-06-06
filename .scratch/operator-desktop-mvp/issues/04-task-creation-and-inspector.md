# Task Creation and Inspector

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/operator-desktop-mvp/PRD.md`

## What to build

Add the end-to-end task creation and inspection experience. The board should show tasks from all repositories by default, support repository filtering, and display compact task cards. Clicking a task opens a right-side inspector. Ready tasks are editable; Review, Done, and Archived tasks are read-only.

The task form should collect title, repository, prompt, and reasoning effort. The prompt is a polished multiline textarea. The model is fixed to `gpt-5.5` and should not be exposed as a free-form input.

## Acceptance criteria

- [ ] The user can create a Task with title, repository, prompt, and reasoning effort.
- [ ] Repository is required.
- [ ] Prompt is required and uses a polished multiline textarea.
- [ ] Reasoning effort options are Low, Medium, High, and Extra High.
- [ ] Reasoning effort internal values are `low`, `medium`, `high`, and `xhigh`.
- [ ] Default reasoning effort is Medium.
- [ ] New Tasks appear in Ready.
- [ ] The board shows tasks from all repositories by default.
- [ ] The board supports filtering by repository.
- [ ] Task cards show title, repo badge, reasoning effort badge, and trigger state badge when relevant.
- [ ] The prompt is shown in the right-side inspector, not on the card.
- [ ] Ready Tasks can be edited.
- [ ] Review, Done, and Archived Tasks are read-only.
- [ ] There is no Backlog column.
- [ ] There is no model selector or free-form model input.

## Blocked by

- `02-sqlite-store-and-task-lifecycle.md`
- `03-repository-registration.md`
