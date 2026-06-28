Status: ready-for-agent

# PRD: Operator Rebrand With Codex Harness

## Problem Statement

Cursor Operator is currently the main product in this repository.
It is a native macOS app for managing local task cards and sending them to Cursor Cloud Agent.
The user wants to add Codex support to this product by using the existing Codex Operator implementation as the source implementation for Codex-specific behavior.

This is not a plan to merge two equal products.
The implementation target is the existing Cursor Operator app and package.
The product should be rebranded to Operator during this integration.
After the integration, Operator should support Cursor and Codex as selectable harnesses for the same local task board.

The MVP should stay small.
Each task chooses exactly one harness before it is sent.
The UI should not introduce multi-agent comparison, parallel execution, rerun-after-success, planning-tool replacement features, or broad execution analytics.

The integration should still create a durable foundation.
Operator should distinguish a Task from a Run.
A Task is the user-facing card.
A Run is one provider execution attempt for that task.
This distinction is required for retry history, provider-specific artifacts, and future harness expansion.

## Solution

Rebrand Cursor Operator to Operator and add Codex as a first-class harness beside Cursor.
Cursor remains the default harness.
Users can change the default harness in Settings and override it while creating or editing a Ready task.

The existing Cursor Cloud Agent flow remains intact.
Cursor tasks continue to run from a GitHub remote source through the Cursor SDK and Node helper.
Cursor API credentials remain in Keychain.
Local dirty state does not block Cursor because Cursor Cloud Agent does not receive local uncommitted changes.

The existing Codex Operator flow is transplanted into Operator.
Codex tasks create a detached worktree under the Codex worktree root, start a Codex thread and initial turn through `codex app-server`, hide the thread while it is running when possible, reveal it when the initial turn completes, and expose the existing Open in Codex App behavior.
Codex does not receive local uncommitted changes from the source checkout.
Codex credentials remain owned by Codex CLI or Codex App.

The board keeps the simple states Ready, Running, Failed, Done, and Archived.
Failed tasks can be edited and retried without creating a new Task card.
Each retry creates a new Run record on the same Task so failed attempts remain auditable.
Done tasks cannot be retried or sent to another harness in the MVP.

The app uses a new Operator identity and local data directory.
The canonical CLI command becomes `operator`.
The old `cursor-operator` CLI compatibility alias is out of scope.
Settings should include Install CLI and Install Skills actions, using the existing Codex Operator agent support work as the reference.

## User Stories

1. As a developer, I want Cursor Operator to become Operator, so that the app name matches its new multi-harness purpose.
2. As a developer, I want the existing Cursor Operator app to be the implementation target, so that Codex support is added to the current main product.
3. As a developer, I want Cursor to remain the default harness, so that the existing Cursor Operator workflow does not surprise current users.
4. As a developer, I want Settings to let me choose the default harness, so that new tasks can default to Cursor or Codex based on my preference.
5. As a developer, I want task creation to let me choose Cursor or Codex, so that each task can use the harness that fits it best.
6. As a developer, I want Ready tasks to allow harness changes, so that I can correct the harness before sending.
7. As a developer, I want sent tasks to lock their harness and settings, so that the recorded Run matches what was actually sent.
8. As a developer, I want one board for Cursor and Codex tasks, so that I can manage agent work in one place.
9. As a developer, I want task cards to show the selected harness, so that I can scan which provider will handle each task.
10. As a developer, I want task cards to show repository and status information, so that I can understand the board quickly.
11. As a developer, I want the board states to remain Ready, Running, Failed, Done, and Archived, so that the MVP stays simple.
12. As a developer, I want Done to mean the provider's initial execution boundary completed, so that Operator does not overstate code correctness.
13. As a developer, I want Failed to mean Operator could not complete the provider handoff or monitoring flow, so that failures are actionable without implying the code is bad.
14. As a developer, I want Failed tasks to remain visible, so that I can fix setup or prompt issues and retry.
15. As a developer, I want to edit a Failed task before retrying it, so that I can repair a bad prompt or provider setting.
16. As a developer, I want retrying a Failed task to keep the same Task card, so that the board does not fill with duplicate cards.
17. As a developer, I want retrying a Failed task to preserve the failed attempt in history, so that I can see what happened before.
18. As a developer, I want Done tasks to be immutable, so that completed history stays trustworthy.
19. As a developer, I want Done tasks not to be rerunnable in the MVP, so that success comparison and rerun semantics do not complicate the first release.
20. As a developer, I want Archived tasks hidden from the default board, so that old work does not clutter active work.
21. As a developer, I want no hard delete in the MVP, so that task history is not accidentally destroyed.
22. As a developer, I want each Task to have internal Run history, so that provider attempts can be audited without creating duplicate Tasks.
23. As a developer, I want Run records to store prompt snapshots, so that later edits do not rewrite what was sent.
24. As a developer, I want Run records to store harness settings snapshots, so that provider-specific execution context is preserved.
25. As a developer, I want Run history in task detail, so that I can inspect failed retries and current provider artifacts.
26. As a developer, I want Cursor tasks to preserve the existing Cursor Cloud Agent flow, so that current Cursor behavior remains reliable.
27. As a developer, I want Cursor repositories to require GitHub origin, so that Cursor Cloud Agent has a remote source it can access.
28. As a developer, I want Cursor sends not to include local uncommitted changes, so that I understand exactly what Cursor will see.
29. As a developer, I want local dirty state not to block Cursor sends, so that cloud runs can start from the remote branch independently.
30. As a developer, I want Cursor sends to avoid automatic fetch, pull, push, merge, or rebase, so that Git network behavior stays under my control.
31. As a developer, I want Cursor API keys stored in Keychain, so that secrets are not stored in SQLite or UserDefaults.
32. As a developer, I want Cursor readiness to show API key and Node status, so that setup issues are visible before sending.
33. As a developer, I want Cursor to keep using fixed model `composer-2.5`, so that model selection does not distract from the integration.
34. As a developer, I want Cursor tasks to keep the auto-create PR toggle, so that I can choose whether Cursor should create a PR.
35. As a developer, I want Open in Cursor to use the saved Cursor Cloud Agent URL, so that I can continue work in Cursor's own surface.
36. As a developer, I want Codex tasks to use the existing Codex Operator runtime behavior, so that proven Codex integration code is reused.
37. As a developer, I want Codex sends to use `codex app-server` over stdio, so that Operator can start Codex work without requiring Codex App to be open.
38. As a developer, I want Operator not to collect Codex credentials, so that Codex login remains owned by Codex CLI or Codex App.
39. As a developer, I want Codex binary detection and override in Settings, so that custom Codex installs can be supported.
40. As a developer, I want Codex readiness to show binary and login status, so that setup failures are clear before sending.
41. As a developer, I want Codex tasks to use fixed model `gpt-5.5`, so that the integrated behavior matches the existing Codex Operator implementation.
42. As a developer, I want Codex tasks to expose reasoning effort `low`, `medium`, `high`, and `xhigh`, so that I can control Codex effort.
43. As a developer, I want Codex worktrees under `~/.codex/worktrees`, so that Codex App sidebar grouping and takeover behavior match the proven implementation.
44. As a developer, I want Codex to start both thread and turn in the prepared worktree, so that continued Codex work stays isolated from my source checkout.
45. As a developer, I want Codex sends not to include local uncommitted changes, so that I understand exactly what Codex will see.
46. As a developer, I want local dirty state not to block Codex sends, so that worktree creation from the default branch remains simple.
47. As a developer, I want Operator to send Git metadata to Codex when available, so that Codex App can group and display threads usefully.
48. As a developer, I want in-flight Codex threads hidden from the normal Codex App sidebar when possible, so that unfinished Operator-triggered threads do not clutter Codex App.
49. As a developer, I want Codex threads revealed when the first turn completes, so that Done tasks are discoverable in Codex App.
50. As a developer, I want Codex hide and reveal to be best-effort, so that sidebar visibility issues do not destroy Run records.
51. As a developer, I want Open in Codex App to prefer the saved Codex thread URL, so that the exact conversation opens when available.
52. As a developer, I want Open in Codex App to fall back to the worktree path, so that I still have a path into Codex if thread deep linking fails.
53. As a developer, I want Operator to send prompts exactly as written, so that hidden prompt augmentation never surprises me.
54. As a developer, I want task titles to stay separate from prompts, so that board labels do not silently change provider instructions.
55. As a developer, I want send preview to show Cursor's remote source model, so that I know local dirty changes are excluded.
56. As a developer, I want send preview to show Codex's detached worktree source model, so that I know the current dirty checkout is excluded.
57. As a developer, I want harness-specific form fields, so that Cursor settings and Codex settings are not confused.
58. As a developer, I want Settings organized around General, Repositories, Cursor, Codex, and Agent Support, so that setup remains understandable.
59. As a developer, I want the app data directory to move to `~/Library/Application Support/Operator`, so that the rebrand is reflected in local storage.
60. As a developer, I want the SQLite database named `operator.sqlite`, so that local data matches the product name.
61. As a developer, I want old Cursor Operator and Codex Operator databases ignored, so that this rebrand is not blocked by migration complexity.
62. As a developer, I want release notes to mention the new local data location, so that users understand why prior local data is not reused.
63. As a coding agent, I want a canonical `operator` CLI, so that I can add tasks and send work without using the UI.
64. As a coding agent, I want the CLI to expose JSON output, so that I can branch on repositories, tasks, runs, and errors reliably.
65. As a coding agent, I want `operator task send` to route by the task's harness, so that I do not need to reimplement provider selection.
66. As a coding agent, I want Codex CLI sends to wait for initial turn completion, so that the spawned app-server is not killed early.
67. As a coding agent, I want Cursor CLI sends to preserve the existing Cursor wait behavior, so that cloud runs can be started and optionally waited on.
68. As a coding agent, I want lifecycle violations to return distinct CLI errors, so that I can explain failures instead of retrying blindly.
69. As a coding agent, I want the installed skill to document Cursor and Codex harness differences, so that I do not assume local dirty state is included.
70. As a maintainer, I want CLI and skill install buttons in Settings, so that agent support can be installed from the app.
71. As a maintainer, I want provider-specific adapters to keep provider-specific names, so that Cursor and Codex code remains understandable.
72. As a maintainer, I want shared domain types renamed away from Cursor-specific names, so that Operator can grow beyond Cursor cleanly.
73. As a maintainer, I want tests around lifecycle, storage, runtime adapters, settings, CLI, and installer behavior, so that the rebrand does not regress existing flows.
74. As a maintainer, I want Codex App worktree and thread visibility regression checks documented, so that Codex CLI upgrades can be validated manually.

## Implementation Decisions

- The implementation target is the existing Cursor Operator package and app.
- The integrated product name is `Operator`.
- The app display name, app data directory, CLI, user-facing docs, and user-facing copy should use `Operator`.
- The Application Support directory is `~/Library/Application Support/Operator/`.
- The SQLite database is `~/Library/Application Support/Operator/operator.sqlite`.
- Existing Cursor Operator and Codex Operator databases are ignored.
- Cursor is the default harness.
- Settings must include a persisted Default Harness setting with `Cursor` and `Codex` choices.
- Task creation uses the configured Default Harness as its initial harness.
- Ready tasks can change harness.
- Running, Done, and Archived tasks cannot change prompt, harness, or harness settings.
- Failed tasks can be explicitly moved back to Ready for editing and retry.
- Retry keeps the same Task card.
- Retry creates a new Run record on the same Task.
- Done tasks cannot be retried in the MVP.
- One Task can have many Runs internally.
- The MVP UI exposes only one selected harness per Task and emphasizes the latest or current Run.
- Multi-harness comparison, parallel runs, and rerun-after-success are future work.
- Board states are Ready, Running, Failed, Done, and Archived.
- Done means the provider's initial execution boundary completed.
- Done does not mean the implementation is correct.
- Failed means Operator failed to complete provider handoff or monitoring.
- Failed does not mean agent output is incorrect.
- Repository records require a local Git checkout with a GitHub origin.
- GitHub origin remains required even for Codex tasks in the MVP.
- Codex-only local repositories without GitHub origin are future work.
- Operator must not fetch, pull, push, merge, or rebase automatically.
- Operator must not hard-delete tasks in the MVP.
- Operator must not automatically clean up Codex worktrees in the MVP.
- Operator must send the task prompt exactly as written for Cursor and Codex.
- Operator must not append hidden instructions, run IDs, worktree paths, repository metadata, or verification commands to prompts.
- Task title remains board metadata and is not silently merged into the prompt.
- Cursor behavior remains aligned with the existing Cursor Operator MVP.
- Cursor uses the official Cursor SDK through the existing small Node helper approach.
- Cursor requires a user-installed Node.js runtime compatible with the SDK.
- The current Node requirement is Node.js 22.13+.
- Cursor API keys are stored in Keychain.
- SQLite and UserDefaults must not store raw Cursor API keys.
- Cursor uses fixed model `composer-2.5`.
- Cursor tasks expose `autoCreatePR`.
- Cursor Cloud Agent starts from the GitHub remote source and selected starting ref.
- Cursor does not receive local uncommitted changes, untracked files, or unpushed commits.
- Local dirty state does not block Cursor sends.
- Cursor Open action uses the saved Cursor Cloud Agent URL in the default browser.
- Codex behavior is transplanted from the existing Codex Operator implementation.
- Codex uses `codex app-server` over stdio.
- Operator lazily spawns `codex app-server` only when sending to Codex.
- Codex App does not need to be open before sending.
- Codex credentials remain owned by Codex CLI or Codex App.
- Operator does not collect or persist Codex credentials.
- Codex Settings include binary auto-detection, absolute binary override, and login/status checks.
- Codex uses fixed model `gpt-5.5` in the MVP because the existing Codex Operator implementation and tests use that model.
- Codex tasks expose reasoning effort `low`, `medium`, `high`, and `xhigh`.
- Codex default reasoning effort is `medium`.
- Codex creates a detached worktree from the registered repository default branch.
- Codex worktrees use `~/.codex/worktrees/<short-run-or-attempt-id>/<repo-name>`.
- Codex `thread/start.cwd` and `turn/start.cwd` both use the prepared worktree.
- Operator must not use the source repository path as `thread/start.cwd` to influence sidebar grouping.
- Operator sends Git metadata through `thread/metadata/update` when available.
- Codex does not receive local uncommitted changes, untracked files, or unpushed commits.
- Local dirty state does not block Codex sends.
- Codex in-flight thread hiding and completion-time reveal are included.
- Codex thread hide and reveal are best-effort.
- Failure to hide does not fail the Run.
- Failure to reveal should surface a short warning when practical while preserving Run completion.
- Open in Codex App preserves the existing Codex Operator behavior.
- Open in Codex App prefers the saved Codex thread URL.
- Open in Codex App falls back to opening Codex with the worktree path.
- Task creation and editing forms switch visible settings by selected harness.
- Cursor fields show `autoCreatePR` and fixed model `composer-2.5`.
- Codex fields show reasoning effort and fixed model `gpt-5.5`.
- Send preview explains Cursor remote source behavior.
- Send preview explains Codex detached worktree behavior.
- Send preview shows the prompt exactly as it will be sent.
- Task detail shows compact Run history.
- Run detail exposes provider artifacts such as Cursor URL, Codex thread URL, Codex worktree path, provider IDs, and sanitized error message.
- Settings are organized around General, Repositories, Cursor, Codex, and Agent Support.
- General Settings include Default Harness, app data path, and About.
- Repositories Settings include local path, GitHub URL, default branch, and repository management.
- Cursor Settings include API key management, environment fallback status, Node readiness, and fixed model information.
- Codex Settings include binary detection, binary override, login/status, and worktree root display.
- Agent Support Settings include Install CLI and Install Skills.
- The canonical CLI command is `operator`.
- The old `cursor-operator` CLI compatibility alias is out of scope.
- The helper executable may be named `operator-cli` internally if product naming requires it.
- The CLI must reuse the app's domain library, store, and lifecycle policies.
- The CLI must not manipulate SQLite directly.
- The initial CLI surface should include repository list/add, task add/list/show/archive/send, and run list.
- CLI JSON schemas include harness fields on tasks and runs.
- CLI errors use distinct exit codes and JSON error codes.
- Codex CLI send waits for initial turn completion because the CLI process owns the spawned app-server.
- A no-wait Codex CLI send is out of scope.
- Cursor CLI send can preserve existing Cursor behavior and may support waiting through the Cursor SDK wait path.
- Installed agent skills document the `operator` command.
- Installed agent skills are thin and call the CLI.
- Installed agent skills must not contain SQL, database paths, lifecycle logic, or provider credentials.

## Testing Decisions

- Tests should verify external behavior and state transitions rather than SwiftUI implementation details.
- Core lifecycle tests should cover Ready, Running, Failed, Done, and Archived transitions.
- Core lifecycle tests should cover Failed to Ready retry without creating a new Task.
- Core lifecycle tests should cover one Task to many Runs.
- Core lifecycle tests should verify Done tasks cannot be retried.
- Core lifecycle tests should verify Ready tasks can edit harness.
- Core lifecycle tests should verify Running, Done, and Archived tasks cannot edit prompt, harness, or harness settings.
- Persistence tests should cover the Operator Application Support database URL.
- Persistence tests should cover repository creation with GitHub URL.
- Persistence tests should cover harness-aware Task creation.
- Persistence tests should cover harness-aware Run creation.
- Persistence tests should cover Run history ordering.
- Persistence tests should cover prompt snapshots and settings snapshots.
- Cursor runtime tests should verify prompt text is sent exactly as written.
- Cursor runtime tests should verify repository URL, starting ref, model, and auto-create PR are sent as provider parameters or metadata.
- Cursor credential tests should verify raw API keys are not stored in SQLite or UserDefaults.
- Cursor readiness tests should verify Node and credential states map to clear user-facing statuses.
- Codex runtime tests should verify prompt text is sent exactly as written.
- Codex runtime tests should verify fixed model `gpt-5.5`.
- Codex runtime tests should verify reasoning effort is passed as a provider parameter.
- Codex worktree tests should verify production configuration uses the `~/.codex/worktrees/<short-id>/<repo-name>` shape.
- Codex app-server tests should verify `thread/start.cwd` and `turn/start.cwd` both use the prepared worktree.
- Codex app-server tests should verify Git metadata update is sent when available.
- Codex visibility tests should verify thread hide is attempted while running.
- Codex visibility tests should verify reveal happens before the task reaches Done when hide succeeded.
- Codex visibility tests should verify hide failure does not fail the Run.
- Codex open tests should verify the thread URL is preferred and the worktree fallback is used when needed.
- Settings tests should verify Default Harness persists.
- Settings tests should verify Cursor readiness combines API key and Node state.
- Settings tests should verify Codex readiness combines binary path and login status.
- Agent support tests should verify CLI and skill installer status without touching real user directories.
- CLI tests should verify `operator` emits stable JSON for repository, task, and run commands.
- CLI tests should verify `task send` routes by task harness.
- CLI tests should verify Codex send waits for initial turn completion.
- CLI tests should verify Cursor send can return after run reference and can wait when requested.
- CLI tests should verify lifecycle violations return distinct errors.
- CLI tests should verify unknown repository and task references return distinct errors.
- Manual Codex regression checks should follow `docs/codex-app-worktree-discovery.md` after Codex worktree changes.
- Manual Codex regression checks should follow `docs/codex-thread-visibility-discovery.md` after Codex thread visibility changes.

## Out of Scope

- Migrating data from the existing Codex Operator database.
- Migrating data from previous Cursor Operator installations.
- Keeping a `cursor-operator` CLI compatibility alias.
- Supporting multiple harnesses for one successful Task.
- Supporting parallel Cursor and Codex runs for the same Task.
- Supporting rerun after success.
- Supporting `Done -> Ready`.
- Building side-by-side harness comparison UI.
- Adding Linear, Notion, GitHub issue, or Slack import.
- Building a general project management system.
- Inspecting diffs.
- Classifying code quality.
- Parsing test output.
- Deciding whether agent output is correct.
- Storing raw Cursor SDK event streams.
- Storing raw Codex app-server event streams.
- Storing transcripts.
- Storing full HTTP bodies.
- Storing secrets outside approved credential stores.
- Automatic fetch, pull, push, merge, or rebase.
- Automatic worktree cleanup.
- Hard delete for tasks.
- Codex-only repositories without GitHub origin.
- Prompt augmentation by Operator.
- First-class Context Pack preview.
- Preflight framework beyond harness readiness needed for MVP sending.
- Model selector for Cursor or Codex.
- Free-form model input.
- Cursor Desktop deep links.
- Codex credential collection.
- Cursor-owned branch or PR orchestration beyond passing `autoCreatePR`.
- Automatic update system.

## Further Notes

- This PRD intentionally treats Cursor Operator as the base product and Codex Operator as the Codex harness source implementation.
- The selected PRD path is `.scratch/operator-rebrand-with-codex/PRD.md`.
- The local issue tracker status is `ready-for-agent`.
- The old product names may remain in implementation file paths temporarily if a complete directory move is too risky, but user-facing names and shared domain names should move to Operator.
- Provider-specific names should remain explicit to avoid hiding important Cursor and Codex differences.
- The strategic backdrop is `docs/operator-agent-execution-strategy.md`.
- The Codex desktop MVP behavior is documented in `docs/operator-descktop-mvp.md`.
- Codex worktree behavior is documented in `docs/codex-app-worktree-discovery.md`.
- Codex thread visibility behavior is documented in `docs/codex-thread-visibility-discovery.md`.
- Cursor MVP behavior is documented in `.scratch/cursor-operator/PRD.md`.
- Agent CLI and skill behavior is documented in `.scratch/operator-skills/PRD.md`.
- Future work includes Codex-only repositories, `Try with another harness`, `Duplicate as new task`, parallel comparison runs, Run comparison UI, Context Pack preview, richer preflight checks, Linear and GitHub integrations, Claude Code support, and explicit data migration if a larger user base needs it later.
