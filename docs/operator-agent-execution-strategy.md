# Operator Agent Execution Strategy

Status: living strategy document  
Last updated: 2026-06-24  
Audience: product strategy, design, implementation, and future agent contributors

## Executive Summary

Operator should evolve from separate Codex and Cursor task boards into a
local-first execution control plane for coding agents.

The durable positioning is:

> Linear is where work is planned. Operator is where agent work is dispatched,
> checked, monitored, resumed, compared, and archived from the developer's
> machine.

Operator should not try to become a better Linear, Notion, GitHub Issues, or
general project-management system. Those products are the system of record for
team planning. Operator should become the local execution layer underneath them:
the place where a developer turns a task, issue, note, failing test, local diff,
or repo state into one or more concrete coding-agent runs.

The long-term opportunity is harness-agnostic agent operations:

- Codex today.
- Cursor Cloud Agent today.
- Claude Code or other local/remote coding agents later.
- Multiple harnesses for the same task when comparison, fallback, or parallel
  execution is valuable.

The product should be described as:

> A local mission control for coding agents.

or:

> A local execution layer for Codex, Cursor, Claude Code, and whatever coding
> agents come next.

## Why This Direction

The market is moving quickly toward agent execution from planning surfaces.
Linear, Notion, Cursor, GitHub, and other developer tools are all adding ways to
start coding agents from issues, docs, comments, and review threads.

That makes a narrow "Kanban UI for Cursor Cloud Agent" fragile. If Operator is
only a board that sends cards to one agent provider, it can be absorbed by the
native planning and IDE surfaces around that provider.

However, those planning surfaces still leave a different job unsolved:

- They do not naturally understand the developer's local working tree.
- They do not own local worktree creation, branch hygiene, local command output,
  transient logs, uncommitted experiments, or machine-specific setup.
- They usually optimize for team coordination, not personal agent operations.
- They are tied to one product's execution model or one source-of-truth system.
- They do not provide a unified run ledger across multiple coding-agent
  harnesses.

Operator's opportunity is to own that layer.

The strategic move is to stop treating the board as the core product. The board
is an entry point. The durable product is the execution system behind it.

## Positioning

### Primary Position

Operator is the local control plane for coding-agent execution across local Git
repositories.

It helps developers:

1. Capture work from local context or external planning tools.
2. Package the right repo context.
3. Select the right agent harness.
4. Run the task safely.
5. Monitor progress.
6. Inspect artifacts.
7. Retry, reroute, or continue in another harness.
8. Keep a durable ledger of what happened.

### What Operator Is

- A local-first agent dispatch console.
- A run ledger for coding agents.
- A context-pack builder for local repositories.
- A preflight checker before agent execution.
- A harness router across Codex, Cursor, Claude Code, and future tools.
- A personal or small-team execution surface that can complement Linear,
  Notion, and GitHub.

### What Operator Is Not

- Not a Linear replacement.
- Not a Notion replacement.
- Not a full issue tracker.
- Not a source-of-truth project-management database.
- Not a generic Kanban board.
- Not a thin wrapper around one provider's API.

### One-Line Messaging Options

- Local mission control for coding agents.
- Dispatch, monitor, and compare coding-agent runs from your Mac.
- Turn local repo state into reliable agent execution.
- The execution layer between your Git repositories and coding agents.
- A local run ledger for Codex, Cursor, Claude Code, and future coding agents.

## Differentiation

### Versus Linear

Linear is excellent for planning, coordination, issue lifecycle, project
visibility, triage, cycles, customer requests, and team-level workflow.

Operator should not compete with that. Operator should integrate with it.

Operator's distinct value:

- Local repo awareness.
- Local preflight checks.
- Local worktree and branch orchestration.
- Harness-specific execution control.
- Multi-agent run history.
- Personal task queue before work becomes a team issue.
- Execution artifacts such as chat session references, Cursor run URLs,
  worktree paths, branches, patches, PR URLs, summaries, and failure reasons.

The clean distinction:

> Linear manages the work. Operator runs the agents.

### Versus Notion + Cursor

Notion can serve as a rich planning and documentation surface where users tag
Cursor or assign database items to a coding agent. That is powerful for teams
that already live in Notion.

Operator's distinct value:

- It starts from local repositories, not docs.
- It can package machine-local context that Notion does not have.
- It can manage runs across more than Cursor.
- It can work for tasks too small or too private to enter Notion.
- It can be invoked by local CLIs, other agents, scripts, and IDE workflows.
- It can preserve local execution metadata even when a provider UI filters or
  hides SDK-created runs.

The clean distinction:

> Notion is a collaborative knowledge and task surface. Operator is the local
> execution console.

### Versus Cursor Native Agents

Cursor owns the Cursor-specific agent experience and will keep improving it.
Operator should not attempt to out-Cursor Cursor.

Operator's distinct value:

- It can dispatch to Cursor when Cursor is the right harness.
- It can dispatch to Codex or Claude Code when those are better fits.
- It can keep a provider-independent ledger.
- It can normalize local context and artifacts across harnesses.
- It can support fallback and comparison across agents.

The clean distinction:

> Cursor is one powerful harness. Operator is the local layer that chooses,
> prepares, records, and compares harnesses.

### Versus Codex App Alone

Codex App is the place to continue Codex sessions. Operator should complement
it by preparing tasks, worktrees, prompts, and follow-up metadata.

Operator's distinct value:

- Local board and run ledger.
- Detached worktree creation.
- Stable CLI for other agents.
- Multi-harness routing beyond Codex.
- Shared task model across future execution providers.

## Target Users

### Primary ICP

Developers who use coding agents heavily across multiple local repositories and
need a reliable way to queue, run, retry, and track agent work.

Traits:

- Uses Codex, Cursor, Claude Code, or similar tools frequently.
- Has multiple local Git repositories.
- Often has small tasks that are not worth creating as formal issues.
- Wants to run agent work while preserving local repo hygiene.
- Needs a record of what was sent, where it ran, and what it produced.

### Secondary ICP

Small teams that use Linear, Notion, or GitHub for planning, but want a local
developer execution layer for coding-agent work.

For this audience, Operator should not replace the planning tool. It should
pull from and push back to it.

### Early Adopter Use Cases

- Queue local coding tasks without opening Linear.
- Send a task to Codex in an isolated worktree.
- Send a task to Cursor Cloud Agent from a local repo.
- Keep a single ledger of Codex and Cursor runs.
- Compare two agents on the same task.
- Retry a failed run with another harness.
- Capture follow-up tasks discovered during review.
- Import a Linear issue or Notion task, run it locally, and attach the result
  back to the source.

## Core Product Concepts

The unified Operator should use a small set of durable domain concepts.

### Repository

A local Git repository registered with Operator.

Repository metadata should include:

- Local path.
- GitHub or remote URL when available.
- Default branch.
- Current branch when relevant.
- Provider-specific requirements such as GitHub origin availability.
- Optional per-repo defaults for test commands, build commands, and agent
  preferences.

### Task

A unit of work that may produce one or more agent runs.

Task metadata should include:

- Title.
- Prompt or task brief.
- Repository.
- Optional source link, such as Linear issue, Notion page, GitHub issue, Slack
  message, or local note.
- Desired artifact, such as patch, PR, explanation, test fix, investigation, or
  follow-up plan.
- Status at the task level.
- User-visible notes and implementation constraints.

Important: a task is not the same as a run. One task may produce multiple runs
across multiple harnesses.

### Context Pack

The package of information sent to an agent or used to prepare an agent run.

Context Pack is the most important strategic concept. It is where Operator can
beat generic planning surfaces.

A Context Pack can include:

- Task prompt.
- Repository identity.
- Current branch.
- Default branch.
- Relevant files.
- `AGENTS.md`, `CLAUDE.md`, skill docs, or repo-specific instructions.
- Local diff summary.
- Dirty worktree status.
- Recent test output.
- Build or lint command output.
- Logs pasted or captured by the user.
- Linked issue or document context.
- Explicit constraints.
- Files or directories the agent should avoid.
- Expected verification commands.

Context Pack should become a first-class previewable artifact. Users should be
able to inspect what will be sent before a run starts.

### Harness

A coding-agent execution provider or runtime.

Initial harnesses:

- Codex.
- Cursor Cloud Agent.

Future harnesses:

- Claude Code.
- GitHub Copilot coding agent.
- Other local or cloud coding-agent runtimes.

Each harness should expose capabilities rather than force a shared lowest common
denominator.

Example capability fields:

- `supportsLocalWorktree`.
- `supportsCloudRun`.
- `supportsWait`.
- `supportsResume`.
- `supportsOpenInApp`.
- `supportsPRCreation`.
- `supportsAutoCreatePR`.
- `supportsModelSelection`.
- `supportsReasoningEffort`.
- `supportsMCP`.
- `supportsEnvVars`.
- `requiresGitHubRemote`.
- `requiresCleanWorktree`.
- `returnsPatch`.
- `returnsBranch`.
- `returnsPR`.
- `returnsChatSession`.
- `returnsRunURL`.

The UI should use these capabilities to explain why a harness is available or
unavailable for a task.

### Run

One execution attempt of one task on one harness.

Run metadata should include:

- Task ID.
- Repository ID.
- Harness ID and version.
- Model or execution profile when available.
- Prompt snapshot.
- Context Pack snapshot or reference.
- Start time.
- Completion time.
- Status.
- Failure reason.
- Provider run ID.
- Provider URL.
- Local worktree path when applicable.
- Branch name when applicable.
- PR URL when applicable.
- Chat/session reference when applicable.
- Verification commands and results.

Runs should be immutable enough to serve as an audit trail. If a task is edited
and rerun, the new run should capture the new prompt/context snapshot.

### Artifact

Anything produced by a run.

Examples:

- Pull request.
- Branch.
- Patch.
- Worktree.
- Codex thread.
- Cursor agent URL.
- Summary.
- Test output.
- Failure message.
- Follow-up task.
- Review note.

Artifacts should be normalized enough to show them in one ledger, while still
preserving harness-specific details.

### Run Ledger

The cross-harness history of all runs.

The Run Ledger should become one of the main product surfaces. It answers:

- What did I send?
- Which harness ran it?
- What context did it receive?
- Did it finish?
- What did it produce?
- Where do I continue?
- Why did it fail?
- Should I retry with the same harness or route to another one?

This is one of the clearest differences from Linear and Notion.

### Preflight

Checks that run before dispatch.

Preflight should protect users from avoidable agent failures and bad context.

Potential checks:

- Repository is registered.
- Repository has a supported remote.
- Default branch is known.
- Worktree is dirty.
- Current branch differs from target branch.
- Local branch is behind remote.
- Large uncommitted diff exists.
- Possible secrets appear in the diff.
- Required CLI is missing.
- Required auth is missing.
- Node/Codex/Cursor/Claude versions are unsupported.
- Harness does not support requested artifact.
- Test command is configured but currently failing.
- Prompt is empty or too vague.
- Context Pack is too large.

Preflight should not always block. Some checks should warn, some should require
confirmation, and some should prevent dispatch.

## Product Principles

### Local-First

Operator should treat the developer's machine as the execution cockpit.

Local state is not incidental. It is the product's advantage.

### Provider-Aware, Not Provider-Locked

Operator should support harness-specific strengths without hardcoding the whole
product around one provider.

Use a shared model for tasks, context packs, runs, and artifacts. Use adapters
for harness-specific behavior.

### Execution Over Planning

Operator can have task cards, columns, and sources, but it should not expand
into full planning workflows unless those workflows directly improve execution.

Avoid building cycles, roadmaps, triage queues, customer requests, team
permissions, and analytics that belong in Linear or Notion.

### Prompt and Context Quality Matter

The product should make it easy to create a complete, standalone instruction for
an agent.

The user should understand:

- What the task is.
- What context will be sent.
- What the agent is expected to produce.
- How the result will be verified.

### Every Run Should Leave a Trail

If an agent does work, Operator should remember what happened.

The record should be durable enough that future users and agents can understand
what was attempted without reconstructing context from multiple provider UIs.

### Integrate Upstream and Downstream

Operator should be able to pull work from planning systems and push results
back, but it should not become the planning system.

Upstream examples:

- Linear issues.
- Notion tasks.
- GitHub issues.
- Slack messages.
- Local markdown files.

Downstream examples:

- Pull requests.
- Branches.
- Patches.
- Run summaries.
- Comments back to Linear, Notion, or GitHub.

## Recommended Product Evolution

### Phase 1: Unify Codex Operator and Cursor Operator

Goal: create one Operator app with a shared task, repository, run, and artifact
model.

Key work:

- Define a shared core package for repositories, tasks, runs, artifacts,
  statuses, lifecycle rules, and storage.
- Treat Codex and Cursor as harness adapters.
- Preserve existing CLIs or provide compatibility wrappers while moving toward
  one `operator` CLI.
- Add a harness field to runs.
- Allow a task to have multiple runs.
- Show Codex and Cursor runs in one ledger.
- Keep provider-specific details visible where useful.

Important migration concern:

- Existing Codex Operator data and Cursor Operator data should be migratable or
  importable.
- If full migration is expensive, provide read-only import or side-by-side
  export first.

Phase 1 success criteria:

- A user can register one repo.
- Create one task.
- Send it to Codex or Cursor.
- See both run types in a single history.
- Open the correct provider artifact from the run detail.

### Phase 2: First-Class Context Pack and Preflight

Goal: make Operator better than planning tools at preparing agent work from
local context.

Key work:

- Add Context Pack preview.
- Include repo instructions such as `AGENTS.md`, `CLAUDE.md`, and relevant
  local docs.
- Summarize Git state.
- Detect dirty worktree and branch conditions.
- Support per-repo verification commands.
- Capture command output into the run record.
- Warn when a harness cannot satisfy the requested task shape.
- Add a prompt quality checklist.

Phase 2 success criteria:

- Before dispatch, the user can inspect the exact context package.
- The app catches common run failures before the agent starts.
- Runs become easier to reproduce and debug.

### Phase 3: Harness Router

Goal: help users choose the right execution harness.

Key work:

- Add a capability matrix for each harness.
- Represent harness availability and auth state.
- Recommend a harness based on task type and requested artifact.
- Allow manual override.
- Support rerun with a different harness.
- Support parallel runs for comparison.

Example routing heuristics:

- Use Codex for tasks that benefit from isolated local worktrees and continued
  conversation in Codex App.
- Use Cursor Cloud Agent for tasks that benefit from cloud execution and
  Cursor's PR automation.
- Use a future Claude Code harness for local terminal-heavy tasks, local
  project setup, or workflows that need direct shell iteration.

Phase 3 success criteria:

- The user can understand why a harness is recommended.
- The user can compare outputs from multiple harnesses on the same task.
- Failed runs can be rerouted without recreating the task manually.

### Phase 4: Integrations Without Becoming the Source of Truth

Goal: make Operator useful inside existing planning systems while preserving its
execution identity.

Key work:

- Import tasks from Linear, Notion, GitHub, or local markdown.
- Preserve source links.
- Push run summaries and artifacts back to source systems.
- Attach PR URLs or failure summaries to the originating issue.
- Keep Operator's local run ledger independent from the upstream tool.

Phase 4 success criteria:

- A Linear issue can become an Operator task.
- A run can produce a PR.
- Operator can update the original source with the result.
- The user still thinks of Linear as planning and Operator as execution.

### Phase 5: Agent Operations and Analytics

Goal: help power users understand which agents work best for which jobs.

Key work:

- Show success/failure rates by harness.
- Show common failure reasons.
- Track run duration.
- Track artifact types.
- Show which repos or task types are most active.
- Provide templates for recurring task categories.
- Suggest follow-up tasks after a run.

Important boundary:

- Keep analytics focused on execution quality, not team productivity or
  management reporting.

Phase 5 success criteria:

- Users can make better decisions about which harness to use.
- Operator becomes more valuable as run history accumulates.

## UX Direction

### Primary Surfaces

Operator should gradually shift from a pure board UI to a few core surfaces:

1. **Dispatch Queue**
   - Tasks ready to be run.
   - Still useful as a Kanban-like entry point.

2. **Run Ledger**
   - Cross-harness execution history.
   - The durable record of agent work.

3. **Task Detail**
   - Prompt.
   - Context Pack.
   - Source links.
   - Runs.
   - Artifacts.
   - Follow-ups.

4. **Context Pack Preview**
   - What will be sent.
   - What was collected from the repo.
   - What checks passed or failed.

5. **Harness Settings**
   - Auth.
   - Capability.
   - CLI paths.
   - Default behavior.

### Board Columns

The old column model can remain, but it should not define the entire product.

Suggested task states:

- Draft.
- Ready.
- Running.
- Needs Review.
- Done.
- Failed.
- Archived.

Suggested run states:

- Pending.
- Preflight Failed.
- Starting.
- Running.
- Succeeded.
- Failed.
- Cancelled.
- Needs Attention.

Task state and run state should be separate. A task may be "Needs Review" while
one run succeeded and another failed.

### Cross-Harness Comparison

When a task has multiple runs, the UI should make comparison easy:

- Prompt snapshot.
- Harness.
- Duration.
- Artifact.
- Verification result.
- Summary.
- Failure reason.
- Continue/open action.

This can become a major differentiator.

## CLI Strategy

The CLI is strategically important because it allows other agents, scripts, and
power users to drive Operator.

The long-term CLI should likely converge on `operator` as the primary command.

Potential command shape:

```text
operator repo list --json
operator repo add <path> --json
operator task add --repo <id-or-name> --title <title> --prompt <text> --json
operator task show <task-id> --json
operator task list --json
operator task archive <task-id> --json
operator context preview --task <task-id> --json
operator preflight --task <task-id> --harness codex --json
operator run start --task <task-id> --harness codex --json
operator run start --task <task-id> --harness cursor --wait --json
operator run list --task <task-id> --json
operator run show <run-id> --json
operator artifact list --run <run-id> --json
```

Compatibility matters:

- Existing `operator` behavior for Codex should remain stable or have a clear
  migration path.
- Existing `cursor-operator` behavior can either remain as an alias or become a
  compatibility wrapper around `operator --harness cursor`.
- JSON output should stay stable and machine-readable.
- Distinct exit codes should remain because agents need to branch on errors.

## Architecture Direction

### Shared Core

Create or evolve a shared domain core that knows about:

- Repositories.
- Tasks.
- Context Packs.
- Harnesses.
- Runs.
- Artifacts.
- Lifecycle rules.
- Storage.
- JSON schemas.

The shared core should not depend on one provider's SDK.

### Harness Adapters

Each harness adapter should own provider-specific details:

- Availability checks.
- Auth checks.
- Prompt/request construction.
- Dispatch.
- Wait/poll behavior.
- Result mapping.
- Artifact extraction.
- Provider-specific error mapping.

Adapters should return normalized run and artifact records.

### Storage

The local SQLite database should become the durable source for:

- Tasks.
- Repositories.
- Runs.
- Artifacts.
- Context Pack snapshots or references.
- Harness metadata.
- Source links.

Provider credentials should not be stored unless there is a secure and explicit
reason. Prefer provider CLIs, system keychain, or existing authenticated tools.

### Data Model Bias

Prefer append-friendly records for runs and artifacts. Avoid overwriting history
that explains what happened.

Task edits are fine, but each run should preserve the prompt/context snapshot
that created it.

## Strategic Non-Goals

Do not prioritize:

- Rebuilding Linear issues.
- Rebuilding Notion docs.
- Team roadmaps.
- Customer request management.
- Sprint/cycle planning.
- Full role-based permissions.
- General analytics dashboards.
- Complex team administration.
- A provider-specific UI clone.

These can become distractions. They pull Operator away from local execution.

## Risks

### Risk: The Product Becomes Too Abstract

Multi-harness support can become vague if the product only says "runs many
agents."

Mitigation:

- Anchor every feature in concrete local execution jobs.
- Keep Codex and Cursor workflows excellent.
- Add new harnesses only when they improve real workflows.

### Risk: Lowest Common Denominator Design

If every harness is forced into the same feature shape, Operator may lose the
strengths of each provider.

Mitigation:

- Use capability-based design.
- Let each harness expose unique actions.
- Normalize only the concepts that matter across all runs.

### Risk: Competing With Planning Tools

Adding issue-tracker features can make Operator look like a weaker Linear.

Mitigation:

- Treat Linear, Notion, and GitHub as sources.
- Push results back to them.
- Keep Operator focused on execution.

### Risk: Provider API Churn

Agent provider APIs and SDKs will change quickly.

Mitigation:

- Keep provider code in adapters.
- Preserve normalized internal records.
- Store enough raw provider metadata for debugging.

### Risk: Local Security and Secrets

Context Pack features may accidentally include secrets or sensitive local data.

Mitigation:

- Add secret detection.
- Let users preview context.
- Make sensitive inclusions explicit.
- Prefer opt-in for logs, env vars, and large diffs.

## Product Decision Checklist

Use this checklist when deciding whether to build a feature.

Build it if it helps users:

- Prepare a better agent task.
- Include the right local context.
- Avoid a failed or unsafe run.
- Dispatch to the right harness.
- Track what happened.
- Continue or inspect the result.
- Retry, compare, or reroute a run.
- Connect execution back to an upstream planning tool.

Be skeptical if it mainly helps users:

- Manage team priorities.
- Replace Linear or Notion.
- Create elaborate project hierarchies.
- Produce management reporting.
- Mirror a provider's native UI without adding local execution value.

## Suggested Near-Term Roadmap

### Immediate

- Write down the shared domain model.
- Decide whether the unified product name is `Operator`, with Codex and Cursor
  as harnesses.
- Add a strategy link from the root README.
- Inventory overlapping code between `codex_operator` and `cursor_operator`.
- Identify the smallest shared storage and CLI schema that supports both.

### Next

- Add `harness` to run records.
- Allow multiple runs per task.
- Build a unified Run Ledger view.
- Add Context Pack preview for at least one harness.
- Add Preflight checks for repo state and provider availability.

### Later

- Add rerun with another harness.
- Add side-by-side run comparison.
- Add Linear/GitHub/Notion import and result writeback.
- Add Claude Code harness once the integration surface is clear.
- Add harness recommendation based on capabilities and task intent.

## Open Questions

- Should `cursor_operator` remain a separate app during transition, or should it
  become a harness inside the main Operator app immediately?
- What is the canonical product name: Operator, Agent Operator, Local Operator,
  or something more explicit?
- Should tasks live in one shared database from the beginning, or should import
  bridge the two existing databases first?
- How much of a Context Pack should be stored verbatim versus referenced by
  path or summarized?
- What is the right security model for local diffs, logs, and secret detection?
- Should parallel multi-agent runs be an early differentiator or a later power
  feature?
- Which upstream integration should come first: Linear, GitHub Issues, Notion,
  or local markdown?

## Final Direction

The durable bet is not "a better Kanban board for agents."

The durable bet is:

> Developers will use multiple coding-agent harnesses, and they will need a
> local, repo-aware control plane to prepare, route, monitor, compare, and
> remember those runs.

Operator should become that control plane.

