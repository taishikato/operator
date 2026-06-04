# Operator Desktop MVP PRD

## Problem Statement

Operator needs to become a native macOS companion app for Codex App: a local-first, Linear-like board for preparing work and sending it to Codex. The current MVP direction is too broad because it treats Operator as an agent runner, scheduler, log owner, Git outcome classifier, and review surface. That makes Operator compete with Codex App instead of complementing it.

The user wants Operator to focus on one job: trigger Codex from a local task board. Codex App should own the detailed thread, transcript, approvals, work progress, diff review, commits, and follow-up work. Operator should own the queue-like task surface, repository binding, local worktree preparation, and the durable reference back to the Codex thread.

## Solution

Build a native SwiftUI macOS app, targeting macOS 15 Sequoia or later, that lets the user create tasks, associate each task with one local Git repository, and send each ready task to Codex through `codex app-server`.

The app uses a mixed-repository Kanban board with repo filtering. A task starts in Ready. When the user sends it to Codex, Operator creates a new detached Git worktree from the repository's local default branch, starts a new Codex thread through app-server with that worktree as the working directory, sends the task prompt as-is, stores the Codex thread reference, and moves the task to Review. From Review, the user opens the task in Codex App to inspect or continue the real work.

Operator does not track Codex completion, does not judge whether Codex succeeded, does not inspect diffs, does not save Codex logs, and does not create PRs in the MVP.

## User Stories

1. As a developer, I want a native macOS Operator app, so that it feels like a desktop sibling of Codex App.
2. As a developer, I want Operator to open directly to a board, so that I can immediately see work to send to Codex.
3. As a developer, I want tasks from all repositories on one board, so that I can manage my Codex queue across projects.
4. As a developer, I want to filter the board by repository, so that I can focus on one codebase when needed.
5. As a developer, I want to register a local Git repository with a folder picker, so that Operator can bind tasks to local code.
6. As a developer, I want Operator to validate that a selected folder is a Git repository, so that task sending fails early for invalid paths.
7. As a developer, I want Operator to infer the local default branch when I add a repository, so that worktrees can start from the expected base.
8. As a developer, I want to edit a repository's default branch in settings, so that I can correct the inferred branch.
9. As a developer, I want to create a task with a title, repository, prompt, and reasoning effort, so that Operator has the minimum context needed to send work to Codex.
10. As a developer, I want the task prompt to be a normal polished multiline textarea, so that writing Codex instructions is simple.
11. As a developer, I want Operator to send exactly the task prompt to Codex, so that Operator does not silently add instructions I did not write.
12. As a developer, I want the model fixed to `gpt-5.5` for the MVP, so that model selection does not become a distraction.
13. As a developer, I want to choose reasoning effort from Low, Medium, High, and Extra High, so that I can tune how much effort Codex spends on a task.
14. As a developer, I want Medium reasoning effort by default, so that new tasks use the same balanced default as Codex App.
15. As a developer, I want each new task to start in Ready, so that the board has no unnecessary Backlog column.
16. As a developer, I want the board columns to be Ready, Review, and Done, so that the lifecycle stays simple.
17. As a developer, I want Archived tasks hidden from the main board, so that completed or discarded work does not clutter active planning.
18. As a developer, I want a Ready task card to show title, repo badge, reasoning badge, and status badges, so that I can scan the board quickly.
19. As a developer, I want prompt details in a right-side inspector, so that the board remains compact.
20. As a developer, I want to send a Ready task to Codex from the card, so that triggering is fast.
21. As a developer, I want to send a Ready task to Codex from the inspector, so that I can review the prompt before sending.
22. As a developer, I want the send action labeled "Send to Codex", so that the UI describes what Operator actually does.
23. As a developer, I want Operator to show "Sending..." while preparing and triggering, so that I know the send request is in progress.
24. As a developer, I want Operator to show "Sent to Codex" after trigger success, so that I know the task reached Codex.
25. As a developer, I want Operator to show "Failed to send" after trigger failure, so that I know the task did not reach Codex.
26. As a developer, I want trigger failure to leave the task in Ready, so that I can fix the issue and retry.
27. As a developer, I want each failed trigger retry to create a new run record, so that failed attempts remain auditable.
28. As a developer, I want each trigger attempt to create a fresh detached worktree, so that failed attempts do not contaminate later attempts.
29. As a developer, I want a successful task to move to Review immediately after Codex is triggered, so that I know it is now waiting for Codex App review.
30. As a developer, I want a successful task to be sent only once, so that Operator does not support rerunning the same task in the MVP.
31. As a developer, I want Review tasks to be immutable, so that the recorded prompt and settings cannot drift after being sent.
32. As a developer, I want Done and Archived tasks to be immutable, so that completed records remain stable.
33. As a developer, I want to move a Review task to Done manually, so that Operator does not infer Codex completion.
34. As a developer, I want to archive Ready, Review, or Done tasks, so that I can remove them from the active board without deleting history.
35. As a developer, I want no hard delete in the MVP, so that local task history is not accidentally destroyed.
36. As a developer, I want no automatic worktree cleanup, so that Operator never deletes local work without explicit user action.
37. As a developer, I want Operator to create worktrees outside the repository, so that nested worktrees do not confuse repo tooling.
38. As a developer, I want Operator-managed worktrees stored under the app data directory, so that all Operator-owned local state is centralized.
39. As a developer, I want Operator to create detached worktrees from the local default branch, so that Codex starts from a clean base without creating a branch.
40. As a developer, I want Operator not to fetch or pull before sending, so that Git network and merge behavior stay outside the MVP.
41. As a developer, I want Operator not to install dependencies before sending, so that Codex decides what setup is needed.
42. As a developer, I want Operator to use `codex app-server`, so that Codex owns the thread and detailed history.
43. As a developer, I want Operator to lazy-start app-server only when sending, so that simply opening Operator does not start Codex runtime work.
44. As a developer, I want Operator to use app-server over stdio, so that the runtime connection avoids port and socket complexity.
45. As a developer, I want Operator to spawn app-server itself, so that Codex App does not need to be open for sending.
46. As a developer, I want app-server events drained but not stored, so that Operator avoids becoming a log database while keeping the process healthy.
47. As a developer, I want Operator to consider trigger success when the Codex thread and first turn are accepted, so that it stops at the trigger boundary.
48. As a developer, I want Operator not to track Codex completion, so that Codex App remains the source of truth for work progress.
49. As a developer, I want Operator not to classify Codex results, so that it does not make false claims about success or failure.
50. As a developer, I want Operator not to inspect changed files or diffs, so that review stays in Codex App.
51. As a developer, I want Operator not to require commits, so that Codex App remains responsible for Git follow-up.
52. As a developer, I want Operator not to create PRs in the MVP, so that GitHub workflow complexity stays out of scope.
53. As a developer, I want Review, Done, and Archived successful tasks to expose "Open in Codex App", so that I can continue or inspect the real thread.
54. As a developer, I want "Open in Codex App" to prefer the saved Codex thread URL, so that the correct conversation opens when possible.
55. As a developer, I want "Open in Codex App" to fall back to opening the worktree in Codex, so that I still have a path into Codex if thread deep linking changes.
56. As a developer, I want Codex binary auto-detection, so that setup works when `codex` is already on my PATH.
57. As a developer, I want a Codex binary path override in Settings, so that I can point Operator at a custom install.
58. As a developer, I want Codex status in Settings, so that I can see whether Operator can send work.
59. As a developer, I want login and authentication handled by Codex CLI or Codex App, so that Operator does not own credentials.
60. As a developer, I want the app database in Application Support, so that local state follows macOS app conventions.
61. As a developer, I want SQLite-backed persistence, so that tasks, repos, and trigger attempts are durable and inspectable.
62. As a developer, I want the app to use a simple Settings surface, so that MVP configuration stays focused on repositories, Codex binary/status, app data path, and About.

## Implementation Decisions

- Operator Desktop MVP is a native SwiftUI macOS app, not an Electron, Tauri, or Next.js desktop wrapper.
- The existing web app remains useful as UI and information architecture reference only.
- The minimum supported OS is macOS 15 Sequoia.
- The local database is SQLite stored in the Operator app data directory.
- GRDB is the preferred Swift SQLite access layer.
- The main screen is the board. There is no landing page or marketing screen.
- The board is mixed-repository by default and supports a repo filter.
- Main board columns are Ready, Review, and Done.
- Archived tasks are available through a separate view or filter and are not shown on the default board.
- New tasks start in Ready.
- Ready is the only state from which a task can be sent to Codex.
- Review, Done, and Archived tasks cannot be sent to Codex.
- Review, Done, and Archived task content is immutable.
- Hard delete is out of scope; archive is the only removal action.
- A task can have at most one successful run.
- Trigger failures can be retried while the task remains Ready.
- Each trigger retry creates a new run record.
- Each trigger attempt creates a new detached worktree.
- A successful trigger moves the task to Review.
- Review to Ready is not allowed in the MVP.
- Rerun is not allowed in the MVP.
- A task belongs to exactly one repository.
- A task stores title, prompt, repository, reasoning effort, status, and timestamps.
- The task prompt is sent to Codex exactly as written.
- Operator does not append hidden instructions, run IDs, worktree paths, or metadata to the prompt.
- The model is fixed to `gpt-5.5` in the MVP.
- Reasoning effort values shown in UI are Low, Medium, High, and Extra High.
- Reasoning effort internal values are `low`, `medium`, `high`, and `xhigh`.
- The default reasoning effort is `medium`.
- Repository registration uses a native folder picker.
- Repository registration validates Git repository status.
- Repository registration infers a local default branch and lets the user edit it later.
- Operator does not fetch, pull, merge, or rebase before sending.
- Operator creates a detached worktree from the repository's local default branch.
- Operator stores the actual base branch and base ref for trigger provenance.
- Operator worktrees live outside the managed repository, under the Operator app data directory.
- Worktrees are not automatically cleaned up.
- Operator does not install dependencies or run setup commands before sending.
- Operator triggers Codex through `codex app-server`.
- Operator spawns `codex app-server` lazily when a send action needs it.
- Operator uses stdio transport for the app-server connection.
- Operator does not require Codex App to be running before a task can be sent.
- Operator starts a new Codex thread for each successful run.
- Operator starts the Codex thread with the run worktree as the working directory.
- Operator then sends one turn containing the task prompt.
- Trigger success means the Codex thread and initial turn were accepted by app-server.
- Operator drains app-server notifications but does not persist raw event streams.
- Operator does not track Codex completion after the trigger boundary.
- Operator does not inspect diffs, changed files, test results, commits, or PR state.
- Operator stores only trigger-level run metadata: task, repository, worktree path, base branch, base ref, Codex thread reference, trigger status, timestamps, and a short error message when sending fails.
- Trigger status values are limited to the trigger lifecycle, such as queued, preparing worktree, triggering, triggered, trigger failed, and canceled.
- Short trigger errors are stored; raw app-server stderr, full JSON-RPC events, and Codex transcripts are not stored.
- "Open in Codex App" is shown for successful Review, Done, and Archived tasks.
- "Open in Codex App" prefers a saved Codex thread deep link.
- If direct thread deep linking is unavailable, Operator falls back to opening Codex with the worktree path.
- Codex binary path is auto-detected and can be overridden in Settings.
- Settings includes repositories, Codex binary path/status, app data path, and About.
- Scheduling, cron, timezone handling, concurrency limits, and trigger queues are not part of the MVP.

Decision-rich state model:

```text
Ready --send accepted--> Review --manual--> Done
Ready --send failed----> Ready + failed badge
Ready --manual archive-> Archived
Review --manual archive-> Archived
Done --manual archive--> Archived

Disallowed:
Review -> Ready
Done -> Ready
Archived -> Ready
successful task -> send again
```

Decision-rich run relationship:

```text
Task
  ├─ failed Run attempt #1
  ├─ failed Run attempt #2
  └─ one successful Run at most

Successful Run
  ├─ one detached worktree
  └─ one Codex thread
```

## Testing Decisions

- Tests should verify external behavior and state transitions, not SwiftUI implementation details.
- Repository detection should be tested with temporary Git repositories, including valid repos, non-repos, missing default branches, and editable default branch configuration.
- Worktree preparation should be tested as a deep module with a simple interface that creates a detached worktree from a repository and branch and returns provenance metadata.
- Worktree preparation tests should verify that no branch is created for the worktree and that base ref metadata is captured.
- Task lifecycle tests should verify allowed and disallowed state transitions.
- Task lifecycle tests should verify that Review, Done, and Archived tasks cannot be edited.
- Send orchestration should be tested with a fake app-server client, so tests can verify trigger behavior without running Codex.
- Send orchestration tests should verify that the task prompt is passed exactly as written.
- Send orchestration tests should verify that `gpt-5.5`, the selected reasoning effort, and the worktree cwd are passed as app-server parameters rather than prompt text.
- Send orchestration tests should verify trigger success moves the task to Review.
- Send orchestration tests should verify trigger failure leaves the task in Ready with a short error.
- Send orchestration tests should verify failed retry creates a new run record and a new worktree.
- Send orchestration tests should verify successful tasks cannot be sent again.
- App-server protocol handling should be tested with a fake JSON-RPC transport that can return success, request errors, malformed messages, and process termination.
- App-server notification draining should be tested enough to ensure the process output is consumed without persisting transcript or event content.
- Deep link construction should be tested separately from OS opening behavior.
- SQLite/GRDB persistence should be tested around migrations, task creation, repository creation, run creation, and immutable post-send task records.
- UI tests should focus on high-value flows: add repository, create task, send to Codex with fake runtime, see Review card, open inspector, and archive.
- Prior art exists in the current web app around task/repo/run concepts and right-side task detail behavior, but the native app should not copy the old runtime assumptions.

## Out of Scope

- Schedule or cron execution.
- Timezone handling.
- Missed schedule handling.
- Trigger concurrency limits.
- Trigger queues beyond immediate send attempts.
- Backlog column.
- Running column.
- Rerun after a successful trigger.
- Review to Ready movement.
- Multiple successful runs per task.
- Multi-repository tasks.
- Model selector.
- Free-form model input.
- Prompt augmentation by Operator.
- Codex completion tracking.
- Codex progress tracking.
- Codex result classification.
- Diff inspection.
- Changed file counts.
- Test result parsing.
- Commit requirements.
- Branch creation for the worktree.
- PR creation.
- GitHub integration.
- Raw JSONL log storage.
- Transcript storage.
- App-server event storage.
- Automatic worktree cleanup.
- Hard delete for tasks.
- Dependency installation before sending.
- Fetching or pulling before sending.
- Codex login UI inside Operator.
- Depending on Codex App being open.
- Electron, Tauri, or Next.js desktop shell implementation.

## Further Notes

- The file name intentionally follows the requested path, including `descktop`.
- Official Codex docs confirm that Codex App has native worktree support, that Codex-managed worktrees live under `$CODEX_HOME/worktrees`, and that app-server exposes thread and turn APIs. The MVP still uses Operator-managed worktrees because the generated app-server schema exposes `cwd`, `model`, and `effort`, but does not expose a stable "create Codex-managed worktree from this branch" request parameter.
- Official Codex docs also show reasoning effort config values including `low`, `medium`, `high`, and `xhigh`; the MVP maps `xhigh` to the Codex App UI label "Extra High".
- This PRD deliberately supersedes the older Cursor SDK, schedule-first, raw-log-owning MVP direction for the desktop MVP.
