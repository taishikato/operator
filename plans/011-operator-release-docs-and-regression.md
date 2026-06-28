# Plan 011: Update Operator release docs and regression checklist

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat c4ec8d4..HEAD -- README.md cursor_operator/README.md cursor_operator/docs cursor_operator/script docs/codex-app-worktree-discovery.md docs/codex-thread-visibility-discovery.md docs/operator-agent-execution-strategy.md .scratch/operator-rebrand-with-codex/PRD.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans/005-operator-rebrand-foundation.md, plans/007-cursor-harness-on-operator-model.md, plans/009-codex-app-server-harness.md, plans/010-operator-cli-and-agent-support.md
- **Category**: docs
- **Planned at**: commit `c4ec8d4`, 2026-06-27

## Why this matters

The integrated app changes name, data location, CLI command, and supported harnesses.
Users and future agents need clear docs that explain what changed and what is intentionally not migrated.
Codex behavior also depends on observed Codex App integration details, so manual regression checks must stay visible near the release process.

## Current state

- Root README currently describes separate Codex Operator and Cursor Operator clients.
- Cursor README describes Cursor Operator only.
- Codex worktree and thread visibility docs already exist in root `docs/`.
- The PRD for this work is `.scratch/operator-rebrand-with-codex/PRD.md`.

Important excerpts:

```markdown
<!-- README.md:1 -->
# Operator

This repository contains native Operator clients for running coding agents against local Git repositories.
```

```markdown
<!-- cursor_operator/README.md:1 -->
# Cursor Operator

Cursor Operator is a native macOS SwiftUI Kanban UI app for Cursor Cloud Agents.
```

```markdown
<!-- docs/codex-app-worktree-discovery.md -->
Operator now starts Codex threads in the run worktree and creates app-visible
worktrees under Codex's worktree root:
~/.codex/worktrees/<short-attempt-id>/<repo-name>
```

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `cd cursor_operator && swift build` | exit 0 |
| Tests | `cd cursor_operator && swift test` | exit 0 |
| Bundle smoke | `cd cursor_operator && ./script/build_and_run.sh --bundle` | exit 0 |
| Markdown scan | `grep -R "Cursor Operator" README.md cursor_operator/README.md cursor_operator/docs docs -n` | remaining matches are intentional historical references |

## Scope

**In scope:**

- Root README.
- Cursor app README, renamed conceptually to Operator app README.
- Distribution docs under `cursor_operator/docs`.
- Release/package script docs if they mention old app names.
- Manual regression checklist docs for Codex worktree and thread visibility.

**Out of scope:**

- Code behavior changes.
- Creating an automatic update system.
- Publishing a release.
- Moving root documentation history.

## Git workflow

- Branch: `codex/operator-release-docs`
- Commit message example: `docs: update operator rebrand docs`
- Do not push unless instructed.

## Steps

### Step 1: Update README product story

Update root and app README so they describe Operator as one native macOS app with Cursor and Codex harnesses.
Mention Cursor is the default harness.
Mention Codex support is included through the Codex harness.
Mention the canonical CLI command is `operator`.

**Verify**: `grep -R "cursor-operator" README.md cursor_operator/README.md -n` -> no user-command references remain unless explicitly called historical/out of scope.

### Step 2: Document data location and no migration

Document:

- Application Support path `~/Library/Application Support/Operator/`
- database `operator.sqlite`
- old Cursor Operator and Codex Operator local databases are not migrated
- users with old local data should treat this as a fresh app state

**Verify**: `grep -R "Application Support/Operator" README.md cursor_operator/README.md -n` -> at least one clear match.

### Step 3: Document harness source models

Explain:

- Cursor runs from GitHub remote/default branch and excludes local dirty state.
- Codex runs from detached worktree created from local default branch and excludes current dirty checkout.
- Operator sends prompts exactly as written.

**Verify**: `grep -R "dirty" README.md cursor_operator/README.md -n` -> docs mention dirty state exclusion for both harnesses.

### Step 4: Document Codex regression checks

Ensure release docs point to the existing worktree and thread visibility discovery docs.
Add a concise manual checklist to release docs if no release checklist exists.
The checklist should include opening a Codex task, verifying cwd under `~/.codex/worktrees`, verifying sidebar visibility behavior, and verifying Open in Codex App.

**Verify**: `grep -R "codex-thread-visibility-discovery" README.md cursor_operator/README.md cursor_operator/docs docs -n` -> a release-facing doc references it.

### Step 5: Final package smoke

Run build, tests, and bundle smoke.

**Verify**:

- `cd cursor_operator && swift build` -> exit 0
- `cd cursor_operator && swift test` -> exit 0
- `cd cursor_operator && ./script/build_and_run.sh --bundle` -> exit 0

## Test plan

This is primarily docs, but the final verification should run build/tests/bundle smoke because docs and scripts often drift together in this repo.
If the bundle smoke requires network for the Cursor SDK helper, use the existing project-approved package workflow or stop and report the blocker.

## Done criteria

- [ ] Root README describes one Operator app direction.
- [ ] App README describes Cursor and Codex harnesses.
- [ ] Docs state `operator` is the canonical CLI.
- [ ] Docs state old Cursor Operator and Codex Operator DBs are not migrated.
- [ ] Docs explain Cursor and Codex source models and dirty-state exclusion.
- [ ] Release-facing docs reference Codex worktree and thread visibility regression checks.
- [ ] `cd cursor_operator && swift test` exits 0.
- [ ] `plans/README.md` status row for plan 011 is updated.

## STOP conditions

Stop and report if:

- Product behavior differs from the PRD or implemented code.
- There is no clear place for release checklist docs and adding one would require a larger docs architecture decision.
- Bundle smoke fails for reasons unrelated to docs.

## Maintenance notes

Docs should be written as the source of truth for future agents.
Avoid promising automatic updates, old DB migration, Codex-only repositories, rerun after success, or multi-harness comparison.
Those are explicitly future work or out of scope.
