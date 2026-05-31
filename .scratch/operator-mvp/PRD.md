Status: ready-for-agent

# PRD: Operator MVP

## Problem Statement

Developers want an open-source, local-first way to queue coding tasks and have AI agents work on them at scheduled times without outsourcing task management to Linear or another external issue tracker. The user wants something conceptually similar to OpenAI Symphony, but centered on Operator's own Kanban board and Cursor SDK-powered agent runs.

The current repository contains a new Next.js web application template under `webapp/`, but it does not yet include Operator's product model, persistence layer, agent runtime integration, scheduler, Git workflow, or PR workflow.

The MVP needs to prove the core loop: a developer adds a Git repository as a Project, creates Tasks in Operator's Kanban, moves ready Tasks into an executable queue, and Operator runs Cursor SDK local agents against those Tasks on demand or on a daily schedule.

## Solution

Operator will be a local-first, source-checkout-first web app. The app runs on `127.0.0.1` with a fixed default port, stores its data outside managed Git repositories in the local app data directory, and uses Cursor SDK local runtime to execute Tasks in local Git repositories.

Operator's own Kanban board is the source of truth. Each Project maps to one Git repository. Each Task belongs to one Project and can specify title, markdown body, acceptance criteria, optional model override, and optional Cursor SDK reasoning-level override. Project-level settings provide default model, default reasoning level, daily schedule settings, scheduled run limit, timeout, and repository metadata.

For the MVP, Operator will focus on task management and execution orchestration. The Cursor agent is responsible for implementation, testing/checking as appropriate, and creating an English commit. Operator observes Git state before and after the run to determine whether the run succeeded.

The first implementation chunk should establish the product design document, persistence foundation, app data directory, basic schema, Project creation, Git repository detection, and the first Add Project experience. Later chunks will add Kanban Tasks, drag-and-drop ordering, Cursor SDK runs, raw logs, scheduling, and draft PR creation.

## User Stories

1. As a developer, I want Operator to provide its own Kanban board, so that I do not need Linear to orchestrate AI coding work.
2. As a developer, I want each Operator Project to map to one Git repository, so that Tasks, branches, commits, and PRs have an unambiguous workspace.
3. As a developer, I want to add a Project by selecting or entering a repository path, so that I can connect Operator to an existing local checkout.
4. As a macOS user, I want a native folder picker for selecting a repository, so that adding a Project feels like a local app.
5. As a non-macOS user, I want a manual path input fallback, so that Operator remains usable outside macOS.
6. As a developer, I want Operator to detect basic repository metadata, so that I do not have to manually enter everything about the Project.
7. As a developer, I want Operator to suggest a short Project key, so that Tasks can have readable IDs like `OP-24`.
8. As a developer, I want to edit the Project key before saving and have it become immutable after saving, so that Task IDs stay stable.
9. As a developer, I want each Task to get a non-reused Project-scoped number, so that references remain stable even after archive operations.
10. As a developer, I want Tasks to have a title, markdown body, and acceptance criteria, so that agents get clear work instructions and completion criteria.
11. As a developer, I want acceptance criteria to remain markdown text in the MVP, so that authoring stays simple.
12. As a developer, I want Task editing to use explicit Save and Discard actions, so that half-written instructions do not get scheduled accidentally.
13. As a developer, I want a markdown preview toggle for Task body and acceptance criteria, so that I can review the agent prompt material before saving.
14. As a developer, I want the Kanban columns to be Backlog, Ready, Running, Review, Done, and Blocked, so that agent execution state is visible.
15. As a developer, I want only Ready Tasks to be scheduled automatically, so that the Kanban column has clear execution meaning.
16. As a developer, I want the order of Tasks within the Ready column to determine execution order, so that I can prioritize work visually.
17. As a developer, I want drag-and-drop column movement and ordering, so that Kanban state and execution order are easy to manage.
18. As a developer, I want moving a Task into Ready to validate Task content, so that empty or ambiguous Tasks do not run automatically.
19. As a developer, I want environment validation to happen at run start, so that I can prepare queues even before all local environment settings are ready.
20. As a developer, I want Tasks to support Project default model and Task-level model override, so that different work can use different Cursor models.
21. As a developer, I want Tasks to support Project default reasoning level and Task-level reasoning override using Cursor SDK values, so that Operator exposes Cursor SDK behavior directly.
22. As a developer, I want model and reasoning options to come from a static list in the MVP, so that the app does not depend on dynamic model discovery.
23. As a developer, I want Operator to add a standard prompt wrapper around Task content, so that every run tells the agent to work in the current repository, run appropriate checks, commit in English, and avoid pushing.
24. As a developer, I want Operator to use Cursor SDK local runtime, so that the MVP remains local-first while still testing Cursor SDK.
25. As a developer, I want Cursor credentials to come from `CURSOR_API_KEY`, so that Operator does not persist Cursor secrets.
26. As a developer, I want GitHub PR creation to rely on `gh` CLI authentication, so that Operator does not need to store GitHub tokens.
27. As a developer, I want each Task to use a branch named from its display ID and slug, so that branches are traceable.
28. As a developer, I want reruns of the same Task to use the same Task branch, so that follow-up commits update the same work item.
29. As a developer, I want Operator to avoid automatic pulls, merges, and rebases, so that local repository state remains under my control.
30. As a developer, I want Operator to skip runs when the working tree is dirty before run start, so that my uncommitted work is not mixed with agent work.
31. As a developer, I want Operator to create or reuse a Task branch before running the agent, so that scheduled work never edits the default branch directly.
32. As a developer, I want the agent to create the commit, so that Operator stays focused on orchestration rather than implementation judgment.
33. As a developer, I want Operator to observe whether HEAD changed during the run, so that success is based on Git facts rather than agent self-reporting.
34. As a developer, I want successful runs to require both a new commit and a clean working tree, so that Review means the branch is ready to inspect.
35. As a developer, I want failed runs to move Tasks to Blocked with a reason, so that failures do not repeat automatically.
36. As a developer, I want canceling a run to move the Task to Blocked, so that a canceled Task does not immediately re-enter the automatic queue.
37. As a developer, I want run timeout to be Project-level with no Task override in the MVP, so that automatic runs cannot continue indefinitely.
38. As a developer, I want run statuses and blocked reasons to be explicit, so that the UI can explain what happened.
39. As a developer, I want full raw run logs stored as JSONL, so that I can debug agent behavior later.
40. As a developer, I want logs to include Cursor SDK events and Operator events, so that both agent output and orchestration steps are visible.
41. As a developer, I want minimal secret redaction before logs are written, so that obvious tokens are not stored by accident.
42. As a developer, I want raw logs stored outside Git repositories, so that sensitive execution details do not get committed accidentally.
43. As a developer, I want raw logs to be retained indefinitely in the MVP, so that historical runs remain available.
44. As a developer, I want the raw log viewer to have a dedicated page, so that long logs are readable.
45. As a developer, I want the raw log viewer to skip custom search in the MVP, so that implementation stays focused and browser search can be used.
46. As a developer, I want Project schedules to be daily structured settings rather than raw cron strings, so that scheduling is understandable.
47. As a developer, I want schedules disabled by default, so that adding a Project never starts automatic work without explicit intent.
48. As a developer, I want missed schedules not to catch up automatically, so that opening Operator later does not unexpectedly start agent runs.
49. As a developer, I want Project schedules to run only while Operator is running, so that local-first behavior is predictable.
50. As a developer, I want scheduled runs to process at most the Project's scheduled run limit, defaulting to one Task, so that morning automation does not create too much work.
51. As a developer, I want manual "Run ready tasks" to default to the scheduled run limit but allow a confirmed count change, so that I can safely run more work when I choose.
52. As a developer, I want batch execution to stop after a failure, so that subsequent Tasks do not run against a potentially bad repository state.
53. As a developer, I want each Project to allow one active run while separate Projects may run concurrently, so that independent repositories can progress in parallel.
54. As a developer, I want duplicate repository paths to be rejected across Projects, so that two Projects cannot operate on the same working tree concurrently.
55. As a developer, I want UI warnings that multiple Projects may start multiple Cursor runs, so that rate limits and cost remain visible concerns.
56. As a developer, I want optional manual draft PR creation, so that agent output can be reviewed through GitHub without forcing pushes automatically.
57. As a developer, I want the Create PR flow to confirm the branch, remote, commit, title, and body before pushing, so that network changes are explicit.
58. As a developer, I want created PRs to be draft PRs, so that agent work is not presented as ready for merge by default.
59. As a developer, I want Tasks to remain in Review after PR creation, so that humans decide when work is Done.
60. As a developer, I want Task archive instead of physical deletion, so that run history and references stay intact.
61. As a developer, I want Project removal to remove it from Operator only, so that the repository, branches, and logs are not deleted.
62. As a developer, I want App settings to show status and read-only operational information, so that I can see app data path, Cursor API key status, and version.
63. As a developer, I want Project settings to hold repo, model, reasoning, schedule, run limit, timeout, and timezone settings, so that Project behavior is controlled in one place.
64. As a developer, I want Settings to be a dedicated page with Project and App tabs, so that settings are not squeezed into the Kanban interface.
65. As a developer, I want selected Project and Task to be reflected in the URL, so that reloads and deep links work.
66. As a developer, I want Project routes to use Project keys, so that URLs are readable.
67. As a developer, I want Task drawer links to use display IDs, so that task URLs match branch and PR naming.
68. As a developer, I want Run URLs to use internal ULIDs, so that each run has a stable unique log page.
69. As a developer, I want the first screen to be Add Project when no Project exists, so that setup begins immediately.
70. As a developer, I want Operator to redirect to the last Project's Kanban after setup, so that the app opens where I last worked.
71. As a developer, I want a dense top bar with Project switcher, schedule status, run controls, New Task, Import Markdown, settings, and theme controls, so that the main workflow is always close.
72. As a developer, I want in-app toast notifications, so that run and PR outcomes are visible without OS-level notification setup.
73. As a developer, I want system theme plus manual theme toggle, so that the local tool fits my environment.
74. As a developer, I want source checkout installation first, so that the OSS MVP is easy to build and inspect.
75. As a developer, I want `operator start` to run the production server, in-process worker, scheduler, app data setup, and first-run DB initialization, so that local operation is one command after build.
76. As a developer, I want `operator db apply` to explicitly apply schema changes, so that existing local and future cloud databases are not changed unexpectedly.
77. As a developer, I want the default host to be `127.0.0.1`, so that the app is not exposed on the network by default.
78. As a developer, I want a fixed default port that errors when busy, so that duplicate Operator instances are obvious.
79. As a developer, I want `operator start --open` to optionally open the browser, so that default CLI behavior remains automation-friendly.
80. As a maintainer, I want the MVP implementation to stay under `webapp/`, so that the codebase stays simple until boundaries justify packages.
81. As a maintainer, I want an explicit DB adapter boundary, so that local Turso storage can later support cloud or sync options.
82. As a maintainer, I want Drizzle schema to be the schema source of truth, so that application types and database shape stay aligned.
83. As a maintainer, I want Atlas declarative apply to update local schema only on first local initialization or explicit command, so that schema changes are controlled.
84. As a maintainer, I want `@tursodatabase/database` with Drizzle beta for the local DB, so that the MVP aligns with Turso local and future Turso Cloud or sync options.
85. As a maintainer, I want Route Handlers and TanStack Query, so that browser UI and future local clients interact through explicit APIs.
86. As a maintainer, I want active-run-only polling, so that run state updates without adding WebSockets in the MVP.
87. As a maintainer, I want TanStack Query plus React local state only, so that state management stays minimal.
88. As a maintainer, I want Zod validation, so that API and form payloads have shared runtime validation.
89. As a maintainer, I want `@dnd-kit` for Kanban drag-and-drop, so that ordering and column moves are reliable.
90. As a maintainer, I want shadcn/base-nova, Tailwind 4, lucide icons, and Sonner to match the existing template, so that UI work follows the current app.

## Implementation Decisions

- Operator's Kanban is the Task source of truth. Linear, GitHub Issues, and other trackers are not required in the MVP.
- The product identity is a local-first web app with a future desktop wrapper path, not a hosted SaaS in the MVP.
- The existing Next.js app under `webapp/` is the implementation home for the MVP.
- Initial distribution is source checkout first: install dependencies, build, then run `operator start`.
- `operator start` runs the production Next.js server plus local worker/scheduler responsibilities. Development uses `pnpm dev`.
- Long Cursor runs must be executed by the local job runner, not by keeping a Route Handler request alive.
- On startup, stale Running Tasks/Runs from a previous process are reconciled to Blocked with reason `interrupted`.
- The app binds to `127.0.0.1` by default. Authentication is out of scope for the MVP because the app is localhost-only.
- The default port is `3927` and should fail clearly if already in use. An `--open` flag can open the browser, but default startup only prints the URL.
- MVP prerequisites are Node.js, pnpm, `CURSOR_API_KEY` for agent runs, `gh` CLI for optional draft PR creation, and Atlas CLI if Atlas remains selected after the DB compatibility spike.
- `operator db apply` is the explicit schema apply command.
- Turso local storage is adopted for the MVP using `@tursodatabase/database` and Drizzle beta. Turso Cloud or sync support is optional future work.
- Drizzle schema is the schema source of truth. Atlas declarative schema apply syncs the DB to that schema.
- First implementation must spike `@tursodatabase/database` + Drizzle beta + Atlas declarative apply before depending on Atlas. If Atlas cannot safely introspect/apply this local DB, the schema apply tool must be revisited before the DB layer is built.
- In local mode, Atlas apply runs automatically only on first DB initialization. Existing databases require explicit apply. Cloud mode will never auto-apply.
- DB and raw logs live in the OS app data directory, not inside managed Git repositories.
- Raw log database references use relative log keys such as `runs/{runId}.jsonl`, not absolute paths.
- IDs use ULID for internal records. Projects also have immutable short keys, and Tasks have non-reused Project-scoped numbers.
- Project keys are globally unique across active Projects.
- Project routes use Project keys. Task drawer URLs use display IDs. Run routes use internal run ULIDs.
- Project equals one Git repository. Duplicate repository paths are rejected.
- Project metadata detection includes repository validity, default branch, remote URL, GitHub slug if available, package manager hints, and presence of local agent instruction files.
- macOS folder browsing is implemented server-side with the native folder picker through `osascript`; browser-only directory handles are not enough because Operator needs absolute repository paths.
- Project settings include default model, default reasoning level, schedule enabled, daily time, timezone, scheduled run limit, and run timeout.
- App settings are status/read-only focused: theme, app data directory, Cursor API key configured/missing, and Operator version.
- Schedule is structured daily scheduling, disabled by default. Missed schedules do not catch up automatically.
- Each Project stores the last scheduled local date that fired, evaluated in the Project timezone, to prevent duplicate daily runs.
- Scheduler timezone math must use a timezone-aware helper instead of naive UTC/local Date arithmetic.
- Scheduler runs only while Operator is running.
- Project concurrency is one active run per Project. Different Projects may run concurrently.
- Ready column order is execution order. `autoRun=false` does not exist in the MVP.
- Scheduled runs process up to `scheduledRunLimit`, defaulting to one Task.
- Manual "Run ready tasks" opens a confirmation dialog with default count equal to `scheduledRunLimit` and an option to run more or all Ready Tasks.
- Batch execution stops after the first failed, canceled, or timed-out Task within that Project. Other Projects may continue independently.
- Kanban columns are Backlog, Ready, Running, Review, Done, and Blocked.
- Running column is system-controlled. Moving into Ready validates only Task content; environment checks happen at run start.
- `Run now` is allowed from Backlog, Ready, Blocked, and Review. It is not allowed from Running or Done.
- Manual run transitions match scheduled run transitions.
- Tasks are archived rather than physically deleted. Archived restoration is out of scope for the MVP.
- Projects are removed from Operator rather than deleting repositories, branches, metadata, or logs. Restore UI is out of scope for the MVP.
- Task input includes title, markdown body, and markdown acceptance criteria. Acceptance criteria are not structured checklist rows in the MVP.
- Task editing uses explicit Save and Discard, not autosave.
- Markdown authoring uses textarea plus preview toggle.
- Model and reasoning level use Project defaults plus Task overrides. Run records store resolved values.
- Reasoning levels are Cursor SDK values exposed directly, stored flexibly as strings. Static UI lists are used for model and reasoning options in the MVP.
- Cursor SDK local runtime is the primary runtime. The runtime adapter boundary should allow future cloud or CLI adapters, but they are not MVP requirements.
- Cursor authentication uses `CURSOR_API_KEY` from the process environment. Operator does not persist Cursor secrets.
- GitHub PR creation uses `gh` CLI and existing `gh` authentication. Operator does not persist GitHub secrets.
- Preflight checks include Cursor API key, repo path existence, Git repo validity, clean working tree, default branch existence, branch checkout/create ability, model presence, and Cursor SDK runtime initialization.
- Operator creates or reuses a Task branch named `operator/{project-key-lower}-{task-number}-{slug}`. The branch name is generated once on first run and stored on the Task.
- Reruns use the stored Task branch and add commits to it. Operator does not automatically pull, merge, or rebase.
- The slug is title-derived at first branch creation only. Branch identity is the Project key plus Task number, not the mutable Task title.
- The Cursor agent is instructed to implement, run appropriate checks, commit in English, and not push.
- Operator success is observed from Git: run-start HEAD differs from run-end HEAD, and the working tree is clean according to `git status --porcelain --untracked-files=all`, excluding ignored files.
- If there is no new commit and the working tree is dirty, the Task becomes Blocked with `worktree_dirty_no_commit`.
- If there is no new commit and the working tree is clean, the Task becomes Blocked with `no_commit_created`.
- If there is a new commit and the working tree is dirty, the Task becomes Blocked with `dirty_after_commit`.
- If there is a new commit and the working tree is clean, the Task moves to Review.
- Dirty working tree before a run blocks the Task without launching the agent.
- `dirty_worktree` is the pre-run dirty state. `worktree_dirty_no_commit` is the post-run state where no new commit exists and uncommitted changes remain.
- `no_commit_created` intentionally treats "nothing changed" as Blocked in the MVP; a human can move the Task to Done if that was correct.
- Canceled runs and timed-out runs move the Task to Blocked with appropriate reasons.
- Raw logs are JSONL and include redacted Cursor SDK events plus Operator events.
- Raw logs are retained indefinitely in the MVP. There is no retention or cleanup policy yet.
- Run summary appears in the Task drawer. Raw log viewing uses a dedicated page with copy/download but no custom search in the MVP.
- Draft PR creation is a manual optional action from Review. The flow confirms branch, remote, commit SHA, title, and body, then pushes and creates a draft PR.
- After draft PR creation, the Task remains in Review with a PR badge. Done is manual.
- Route Handlers are the API layer. TanStack Query handles server state, optimistic Kanban updates, and active-run polling.
- Polling is active-run-aware: active runs poll frequently, inactive state avoids constant polling. SSE/WebSocket are out of scope for MVP.
- UI stack follows the template: Tailwind 4, shadcn/base-nova, lucide-react, next-themes, Sonner, and `@dnd-kit`.
- Settings are a dedicated page with Project and App tabs.
- The first implementation chunk includes the PRD/design doc, DB compatibility spike, DB/app data/schema foundation, Add Project flow, Git repo detection, Project creation, and first route behavior.

### Major Modules

- App data module: resolves OS app data directory, creates required directories, and exposes relative log key helpers.
- Database module: creates the Turso local database connection, exposes Drizzle schema, and keeps driver details behind a narrow boundary.
- Schema/apply module: integrates Drizzle schema with the selected declarative apply path for first local initialization and explicit apply, after the Turso/Drizzle/Atlas compatibility spike.
- Project repository module: creates, reads, updates, removes, and validates Projects.
- Git inspection module: detects repository metadata, default branch, remote URL, GitHub slug, clean state, branch existence, and HEAD state.
- Project onboarding module: validates Add Project input, suggests immutable Project keys, detects metadata, and creates Project records.
- Native folder picker module: provides macOS folder picker and manual fallback behavior.
- Task repository module: manages Tasks, numbering, status transitions, sorting, archive state, and validation.
- Run orchestration module: preflight checks, branch setup, prompt wrapper creation, Cursor SDK run lifecycle in the local job runner, timeout/cancel, Git observation, startup reconciliation, and state transitions.
- Raw log module: writes redacted JSONL events, exposes log metadata and retrieval for the UI.
- Scheduler module: daily Project schedule evaluation, missed-schedule handling, scheduled run limit, and per-Project concurrency.
- PR module: detects GitHub/gh readiness and creates draft PRs through an explicit confirm-and-run flow.
- UI modules: Add Project, Kanban board, Task drawer, Settings page, Run raw log page, top bar, dialogs, and toasts.

## Testing Decisions

- Good tests should verify external behavior and durable state transitions, not internal implementation details.
- Deep modules should get focused unit tests where practical: Git inspection, Project onboarding, Task state transitions, branch naming, run result classification, raw log redaction, schedule selection, and schema/app data helpers.
- Integration tests should cover Route Handler contracts for Project creation, Task mutation, run initiation, and settings updates once those APIs exist.
- UI tests should focus on user-observable flows such as Add Project, Ready validation, drag-and-drop ordering, Task drawer save/discard, and settings persistence.
- Cursor SDK agent execution should be tested through an adapter seam with fakes for most automated tests. Real Cursor SDK runs should be manual or opt-in because they require credentials, local repos, and may incur cost.
- Git operations should be tested against temporary Git repositories where possible, including clean/dirty detection, branch naming, HEAD delta detection, and duplicate repo path rejection.
- Native folder picker should be unit-tested around fallback behavior and manually verified on macOS.
- Scheduler tests should use controlled clocks and Project timezones to verify daily schedule selection, missed schedule non-catch-up, and scheduled run limit behavior.
- Raw log tests should verify JSONL append behavior, relative log keys, copy/download payload shape, and minimum secret redaction.
- Draft PR creation should be tested with a command adapter fake in automated tests. Real `gh` CLI behavior should be manually verified.
- There is little prior test structure in the repo today, so the first implementation should add a lightweight test runner only when the first deep module needs it.

## Out of Scope

- Hosted SaaS Operator.
- Central Operator server operated by the project owner.
- Linear as source of truth.
- GitHub Issues import.
- Linear import/sync.
- Bidirectional tracker sync.
- Multi-user authentication.
- Remote/LAN exposure.
- Cursor Cloud Agents as the primary runtime.
- Cursor CLI as the primary runtime.
- Self-hosted worker architecture.
- Desktop wrapper, login item, OS startup integration, or OS notifications.
- Automatic missed schedule catch-up.
- Automatic Git pull, merge, rebase, or conflict resolution.
- Automatic push or PR creation after every successful run.
- GitHub App or OAuth integration.
- App-managed Cursor or GitHub secret storage.
- Human assignees and general team PM features.
- AgentProfile abstraction beyond model and reasoning level.
- Task dependencies, parent/child Tasks, labels, due dates, or priority fields.
- Structured acceptance criteria checklist state.
- Raw log retention/cleanup settings.
- Custom raw log search/filtering.
- Global concurrency cap for all Projects.
- Cost tracking or rate-limit prediction.
- Archived Task restore UI.
- Removed Project restore UI.
- NPM global package distribution.
- Docker-first distribution.
- Turso Cloud required mode.
- Atlas versioned migrations.

## Further Notes

- The MVP should be implemented as a vertical slice rather than a complete UI shell first. The first meaningful user outcome is adding a Project and establishing the local persistence foundation.
- Operator should remain honest about local-first limitations: schedules require the app to be running, missed schedules do not run automatically, and raw logs may contain sensitive information even after basic redaction.
- Future cloud support should be protected by storage boundaries, not by prematurely making the MVP cloud-dependent.
- Future desktop support should reuse the web app surface and replace local helper pieces such as folder picking with native APIs.
- Existing superpowers-generated docs should not drive this product plan; this PRD is the working source for the Operator MVP scope.
