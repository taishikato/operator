Status: ready-for-agent

# PRD: Cursor Operator MVP

## Problem Statement

The user has a native Codex Operator desktop app that provides a small local task board for sending work to Codex App. The user now wants a separate Cursor-focused Operator that keeps the same disciplined product shape, but targets Cursor Cloud Agent instead of Codex.

The existing Cursor-oriented web app is too broad for this direction. It acts as a local Cursor SDK runner, owns branch setup, raw logs, result classification, scheduling, and draft PR creation. The user wants the Cursor version to be a native macOS desktop app, not a Next.js web app, and wants each Operator codebase to stay small by keeping the Cursor app separate from the Codex app.

The MVP should not become a general project management tool, a GitHub PR orchestrator, a local agent runtime, or a Cursor result judge. It should be a desktop queue for preparing tasks and starting Cursor Cloud Agent runs from GitHub repositories that are already represented by local checkouts.

## Solution

Build a separate native SwiftUI macOS app called Cursor Operator. The app gives the user a local Kanban board for Cursor tasks. The user registers local Git repositories that have a GitHub origin, creates Ready tasks with a title, repository, prompt, and auto-create PR setting, then sends a task to Cursor Cloud Agent.

Cursor Operator starts a Cursor Cloud Agent run from the repository's remote default branch. The app sends the task prompt exactly as written, passes the Cursor model as a runtime parameter, and saves the resulting Cursor agent reference and open URL. Cursor remains the source of truth for agent progress, work continuation, generated branches, PRs, code review, and final outcome.

The MVP is a native desktop app, not a web app. It is a separate Swift package and app from Codex Operator, with separate persistence, settings, bundle identity, and Application Support data. Existing Codex Operator code and the old Cursor web app may be used as reference material, but there is no shared package in the MVP.

## User Stories

1. As a developer, I want Cursor Operator to be a native macOS desktop app, so that it feels like a local companion to my coding workflow.
2. As a developer, I want Cursor Operator to be separate from Codex Operator, so that each Operator codebase stays small and focused.
3. As a developer, I want Cursor Operator to open directly to a task board, so that I can immediately see work that can be sent to Cursor.
4. As a developer, I want a board with Ready, Running, Done, and Archived states, so that the task lifecycle stays simple.
5. As a developer, I want Archived tasks hidden from the default board, so that old work does not clutter active planning.
6. As a developer, I want to register a local Git repository, so that Cursor Operator can bind tasks to a real codebase on my machine.
7. As a developer, I want repository registration to require a GitHub origin, so that Cursor Cloud Agent can run from a remote repository it can access.
8. As a developer, I want Cursor Operator to detect the repository default branch, so that Cursor Cloud Agent can start from the expected base.
9. As a developer, I want to review or edit the detected GitHub URL and default branch before saving a repository, so that detection mistakes can be corrected.
10. As a developer, I want GitHub-only repository registration to be out of scope, so that every repository in Cursor Operator still maps to a local checkout.
11. As a developer, I want local dirty files not to block sending, so that Cursor Cloud Agent can run from the remote default branch independently of my local working tree.
12. As a developer, I want the UI to make it clear that Cursor Cloud Agent starts from the remote default branch, so that I do not expect local unpushed changes to be included.
13. As a developer, I want Cursor Operator not to fetch, pull, push, merge, or rebase automatically, so that Git network behavior stays under my control.
14. As a developer, I want each task to belong to exactly one repository, so that Cursor Cloud Agent has an unambiguous source.
15. As a developer, I want each Ready task to have a title, repository, prompt, and auto-create PR setting, so that the task captures only the minimum information needed to start a Cursor run.
16. As a developer, I want the prompt editor to be a polished multiline text area, so that writing Cursor instructions is comfortable.
17. As a developer, I want Cursor Operator to send my prompt exactly as written, so that hidden instruction changes do not surprise me.
18. As a developer, I want task title to be stored separately from the prompt, so that the board remains scannable without changing what Cursor receives.
19. As a developer, I want acceptance criteria, labels, assignees, priorities, due dates, and dependencies to be out of scope, so that the MVP remains a task queue rather than a project management system.
20. As a developer, I want the Cursor model fixed to composer-2.5 in the MVP, so that model selection does not distract from the core workflow.
21. As a developer, I want the fixed model displayed in the send preview, so that I know which Cursor model will be used.
22. As a developer, I want auto-create PR to be a task-level toggle, so that I can choose whether Cursor Cloud should create a PR for that run.
23. As a developer, I want auto-create PR to default off, so that a new task does not create a PR unless I asked for it.
24. As a developer, I want branch naming and PR details to be owned by Cursor Cloud, so that Cursor Operator does not become a branch or PR orchestration tool.
25. As a developer, I want a Ready task to be editable, so that I can refine the prompt before sending.
26. As a developer, I want Running, Done, and Archived task content to be immutable, so that the Operator record continues to match what was sent to Cursor.
27. As a developer, I want to send a Ready task to Cursor from the board, so that starting a run is fast.
28. As a developer, I want to send a Ready task from the task detail surface, so that I can review the prompt before sending.
29. As a developer, I want a send preview to show repository URL, starting ref, fixed model, auto-create PR setting, and prompt, so that I can verify the exact run context.
30. As a developer, I want sending to show an in-progress state, so that I know Cursor Operator is contacting Cursor Cloud.
31. As a developer, I want a successful send to move the task to Running, so that I can see which tasks have been handed to Cursor.
32. As a developer, I want Cursor Operator to save the Cursor agent run id and open URL, so that I can get back to the run later.
33. As a developer, I want Running tasks to expose Open in Cursor, so that I can inspect or continue the run in Cursor's own surface.
34. As a developer, I want Open in Cursor to open the Cursor Cloud Agent web URL in the default browser, so that the MVP uses the most reliable available destination.
35. As a developer, I want Cursor Desktop deep links to be out of scope, so that the MVP does not depend on unstable desktop linking behavior.
36. As a developer, I want Cursor run status polling to be out of scope, so that Cursor remains the source of truth for progress.
37. As a developer, I want webhooks to be out of scope, so that the MVP does not need a public callback endpoint.
38. As a developer, I want Done to be a manual state, so that I decide when the task is cleared from the active workflow.
39. As a developer, I want Done not to imply that Cursor produced correct code, so that Operator does not overstate agent results.
40. As a developer, I want to archive Ready, Running, or Done tasks, so that I can remove work from the active board without deleting history.
41. As a developer, I want no hard delete in the MVP, so that local task history is not accidentally destroyed.
42. As a developer, I want a failed send to leave the task in Ready, so that I can edit and retry it.
43. As a developer, I want each failed retry to create a separate run attempt, so that failed attempts remain auditable.
44. As a developer, I want failed send errors to be short and sanitized, so that secrets and noisy HTTP bodies are not stored.
45. As a developer, I want a task to have at most one successful Cursor send, so that rerun behavior does not complicate the MVP.
46. As a developer, I want Cursor API credentials to be stored in macOS Keychain, so that secrets are not stored in SQLite or UserDefaults.
47. As a developer, I want Settings to let me paste, validate, mask, and delete the Cursor API key, so that credential management is understandable.
48. As a developer, I want a development fallback to the CURSOR_API_KEY environment variable, so that local development and tests remain convenient.
49. As a developer, I want Send disabled or blocked when no Cursor API key is available, so that I get a clear setup failure before a run attempt.
50. As a developer, I want Cursor Operator to call Cursor Cloud Agent through a native Swift REST client if possible, so that the desktop app does not need to bundle Node.
51. As a developer, I want an API schema spike before implementation relies on the REST client, so that endpoint paths, request fields, response fields, and error shapes are verified against Cursor's current API.
52. As a developer, I want a Node helper using the Cursor SDK to stay a fallback option, so that implementation can recover if the REST API is not stable enough.
53. As a developer, I want Cursor Operator to keep raw agent logs out of scope, so that local storage does not become a transcript database.
54. As a developer, I want Cursor Operator not to inspect diffs, commits, tests, PR status, or branch names, so that review stays in Cursor and GitHub.
55. As a developer, I want the app to store tasks, repositories, run attempts, settings metadata, and Cursor run references in a local SQLite database, so that the board is durable.
56. As a developer, I want the app data path, app identity, and database to be separate from Codex Operator, so that the two apps cannot corrupt each other's state.
57. As a developer, I want the app to use native macOS settings, toolbar, sidebar, detail, and inspector patterns, so that it behaves like a desktop app rather than a web shell.
58. As a developer, I want keyboard and menu access for common actions, so that the app is efficient for repeated use.
59. As a developer, I want repository and Cursor credential status visible in Settings, so that setup issues are easy to diagnose.
60. As a developer, I want implementation issues to be able to test deep modules in isolation, so that API, persistence, repository detection, and lifecycle behavior are reliable without UI-heavy tests.

## Implementation Decisions

- Cursor Operator is a separate native SwiftUI macOS app and Swift package from Codex Operator.
- Cursor Operator does not reuse Codex Operator's database, bundle identity, Application Support directory, or runtime implementation.
- Codex Operator and the old Cursor web app are reference implementations only for product shape, domain concepts, and prior test patterns.
- The primary scene is a desktop board window. Settings is a native Settings scene, not a route inside the main board.
- The main window should use desktop SwiftUI patterns: sidebar or board navigation, task detail/inspector surface, toolbar actions, command menu actions, keyboard shortcuts, and stable selection state.
- The app should keep root view composition small and split app entry, views, models, stores, services, and support helpers by responsibility.
- The board states are Ready, Running, Done, and Archived.
- Ready tasks are editable and sendable.
- Running, Done, and Archived task content is immutable.
- Running to Done is manual in the MVP.
- A successful send moves a task from Ready to Running.
- A failed send leaves a task in Ready with a failure badge.
- Archived tasks are hidden from the default board.
- Hard delete is out of scope.
- Rerun after a successful send is out of scope.
- Each task can have at most one successful Cursor run reference.
- Failed attempts may be retried and each retry creates a new run attempt.
- A task belongs to exactly one repository.
- A repository record represents one local Git checkout with a GitHub origin.
- GitHub-only repository records are out of scope in the MVP.
- Repository registration uses a native folder picker.
- Repository registration validates that the selected folder is a Git repository.
- Repository registration requires a GitHub origin URL that can be converted into the repository URL Cursor Cloud Agent expects.
- Repository registration detects the default branch and lets the user review or edit it before saving.
- Cursor Cloud Agent runs start from the remote default branch, not from local uncommitted state.
- Local dirty files and unpushed commits do not block sending because the Cloud Agent source is the remote default branch.
- The UI must clearly show that local-only changes are not part of the Cursor Cloud Agent source.
- Operator does not automatically fetch, pull, push, merge, or rebase in the MVP.
- The Cursor Cloud Agent model is fixed to composer-2.5 in the MVP.
- Model selector and dynamic model discovery are out of scope.
- Auto-create PR is a task-level setting.
- Auto-create PR defaults off.
- Cursor owns branch naming, branch lifecycle, PR title/body, PR creation details, and PR review status.
- Cursor Operator may pass the auto-create PR boolean to Cursor, but it does not create PRs itself.
- Task prompt is sent exactly as written.
- Task title, repository metadata, starting ref, model, and auto-create PR are sent as runtime parameters or stored metadata, not hidden prompt augmentation.
- The send preview shows repository URL, starting ref, model, auto-create PR setting, and prompt.
- Cursor API key is stored in macOS Keychain.
- SQLite and UserDefaults must not store the raw Cursor API key.
- Settings supports entering, masking, validating, and deleting the Cursor API key.
- A development fallback to the CURSOR_API_KEY environment variable is allowed.
- The Cursor runtime client is a deep module with a narrow interface for starting a Cloud Agent run.
- The preferred MVP implementation is a Swift REST client using URLSession.
- The first implementation chunk must include an API schema spike that verifies Cursor Cloud Agent endpoint path, auth header, request body, success response, error response, agent URL field, run id field, and auto-create PR field.
- If the REST API is not stable enough for a native client, a Node helper using the Cursor SDK remains an implementation fallback.
- Cursor Operator saves only trigger-level metadata for a run attempt: task, repository, starting ref, fixed model, auto-create PR value, status, timestamps, Cursor agent id, open URL, and short failure error.
- Raw Cursor event streams, transcripts, full HTTP bodies, and secrets are not stored.
- Cursor run status polling is out of scope.
- Cursor webhook support is out of scope.
- Open in Cursor opens the saved Cursor Cloud Agent web URL in the default browser.
- If a direct agent URL is unavailable, the app should provide a fallback that lets the user copy the run id or open Cursor's Cloud Agent dashboard.
- Cursor Desktop deep links are out of scope.
- The local database should be SQLite-backed.
- GRDB is the likely Swift SQLite layer because the existing desktop app already proves it works well for this repository's native app style.
- The persistence module is a deep module with a stable interface for repositories, tasks, run attempts, settings metadata, and lifecycle transitions.
- The repository detection module is a deep module with a stable interface that returns Git validity, origin URL, GitHub URL, and default branch metadata.
- The task lifecycle policy is a deep module that owns allowed transitions, immutability rules, retry rules, and one-successful-run constraints.
- The Keychain credential store is a deep module with a narrow save/load/delete/validate-facing interface.
- The app should keep API client, repository detection, credential storage, lifecycle policy, and persistence testable without SwiftUI.

## Testing Decisions

- Tests should verify external behavior and state transitions, not SwiftUI implementation details.
- Repository detection tests should use temporary Git repositories where practical.
- Repository detection tests should cover valid GitHub origin, missing origin, non-Git folder, unsupported remote URL, detected default branch, and editable default branch metadata.
- Task lifecycle tests should verify Ready, Running, Done, and Archived transitions.
- Task lifecycle tests should verify that Ready tasks are editable and Running, Done, and Archived tasks are immutable.
- Task lifecycle tests should verify that failed send attempts leave the task Ready.
- Task lifecycle tests should verify that successful send attempts move the task Running.
- Task lifecycle tests should verify that a task cannot be successfully sent twice.
- Task lifecycle tests should verify that failed retries create separate run attempts.
- Persistence tests should cover repository creation, task creation, run attempt creation, failed attempt metadata, successful Cursor references, archived tasks, and immutable sent task records.
- Cursor API client tests should use a fake HTTP transport.
- Cursor API client tests should verify the request sends prompt text, repository URL, starting ref, composer-2.5, and auto-create PR as API fields rather than hidden prompt text.
- Cursor API client tests should verify success response mapping into agent id and open URL.
- Cursor API client tests should verify authentication failures, validation failures, malformed responses, network failures, and short sanitized error messages.
- Cursor API schema spike should be captured as either a test-backed fixture or a short implementation note before the runtime client is considered complete.
- Keychain credential store tests should use an injectable credential storage abstraction so unit tests do not depend on the developer's real Keychain entries.
- Settings model tests should verify key present/missing status, environment fallback behavior, validation result mapping, and deletion behavior.
- Open in Cursor tests should verify URL selection and fallback behavior separately from OS-level browser opening.
- UI tests should focus on high-value flows only: add repository, create task, send with fake Cursor runtime, see Running card, open task detail, mark Done, and archive.
- Prior art exists in the native Codex app tests for SQLite persistence, repository registration, task lifecycle policy, runtime guardrails, and trigger service tests.
- Prior art exists in the old Cursor web app tests for Cursor-oriented run orchestration concepts, but the MVP should not copy its local SDK runner, raw log, branch classification, scheduling, or PR creation assumptions.

## Out of Scope

- Next.js web app implementation.
- Sharing a codebase, database, or runtime package with Codex Operator.
- GitHub-only repository registration.
- Local Cursor Desktop runtime.
- Local Cursor SDK runner behavior.
- Bundling Node as the default runtime path.
- Scheduling, cron, timezone handling, missed schedule catch-up, and batch queues.
- Raw log capture, raw event storage, transcript storage, and log viewer UI.
- Cursor run status polling.
- Cursor webhook support.
- Cursor Desktop deep links.
- Dynamic model discovery.
- Model selector.
- Reasoning selector.
- Prompt augmentation by Operator.
- Acceptance criteria fields.
- Labels, assignees, priorities, due dates, dependencies, and structured checklists.
- Operator-owned branch naming.
- Operator-owned branch creation.
- Operator-owned PR creation.
- PR title/body editing.
- PR review state tracking.
- Diff inspection.
- Changed file counts.
- Test result parsing.
- Commit requirements.
- Cursor result classification.
- Automatic fetch, pull, push, merge, or rebase.
- Hard delete.
- Rerun after a successful send.
- Multiple successful runs for one task.
- Storing Cursor API keys in SQLite or UserDefaults.

## Further Notes

- The selected product direction is Cursor Cloud Agent first, not local Cursor first.
- The selected app shape is a native SwiftUI macOS desktop app, not a web app.
- The selected codebase shape is a separate Cursor Operator package/app, not a unified Codex-plus-Cursor Operator.
- The selected runtime direction is REST first with an API schema spike required before implementation depends on specific Cursor Cloud Agent request and response shapes.
- Public Cursor material shows SDK Cloud Agent creation with repository URL, starting ref, model id, auto-create PR, and prompt. The REST API details must still be verified during the spike because the public surface can change.
- Cursor Cloud Agent web URL is the MVP continuation surface. Cursor Desktop integration can be revisited after the cloud flow is proven.
