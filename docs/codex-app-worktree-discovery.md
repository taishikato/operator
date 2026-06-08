# Codex App Worktree Discovery

This document captures the Codex App worktree behavior discovered while fixing
Operator Desktop thread takeover and sidebar grouping.

## Date

2026-06-09

## Why This Matters

Operator sends local tasks to Codex App by preparing a detached Git worktree,
starting a Codex thread through `codex app-server`, and saving the resulting
thread deep link.

Two user-facing properties must both hold:

- Continuing the thread in Codex App must stay inside the run worktree.
- The thread should still appear under the source repository in Codex App's
  sidebar.

The first property protects the user's main checkout. The second property keeps
Operator-created Codex work discoverable in the same place as Codex-created
work.

OpenAI's public Codex App materials describe isolated worktree support, but they
do not document the app-server fields or sidebar grouping rules. The behavior
below comes from local observation of Codex App session data and app-server
requests.

## Initial Problem

Operator originally created a detached worktree for every send attempt, but it
started Codex with different directories for the thread and the turn:

- `thread/start.cwd`: source repository path
- `turn/start.cwd`: detached worktree path

This made Codex App list the thread under the source repository, but when the
user opened or continued the thread in Codex App, the saved thread working
directory was the source repository. Takeover could therefore happen in the main
checkout instead of the isolated worktree.

The first fix changed `thread/start.cwd` to the worktree path. That fixed
takeover isolation, but Operator-created threads stopped appearing under the
source repository in the Codex App sidebar.

## Evidence

### Operator-Created Thread Before The Fix

Observed shape:

```text
thread/start.cwd = /Users/.../Work/focus/projects/web-pic
turn/start.cwd   = /Users/.../Library/Application Support/Operator/worktrees/<repo-id>/<attempt-id>
```

Result:

- Sidebar grouping worked because the saved thread cwd was the source repo.
- Codex App takeover used the saved thread cwd and returned to the source repo.
- Worktree isolation was not reliable after takeover.

### Operator-Created Thread After The First Fix

Observed shape:

```text
thread/start.cwd = /Users/.../Library/Application Support/Operator/worktrees/<repo-id>/<attempt-id>
turn/start.cwd   = /Users/.../Library/Application Support/Operator/worktrees/<repo-id>/<attempt-id>
```

Result:

- Codex App takeover stayed in the worktree.
- The thread opened correctly through `codex://threads/<thread-id>`.
- The thread did not appear under the source repository in the Codex App
  sidebar.

Adding `thread/metadata/update` with `gitInfo` helped persist git metadata, but
it was not enough by itself to restore sidebar grouping for a local-only repo.

### Codex-App-Created Worktree Thread

A thread created directly from Codex App using "New worktree" had this shape:

```text
cwd = /Users/taishi/.codex/worktrees/6783/operator
source = vscode
thread_source = user
git_origin_url = git@github.com:taishikato/operator.git
git_branch = ""
```

Git facts from that worktree:

```text
git rev-parse --show-toplevel
  /Users/taishi/.codex/worktrees/6783/operator

git rev-parse --git-common-dir
  /Users/taishi/Work/focus/projects/operator/.git

git remote get-url origin
  git@github.com:taishikato/operator.git
```

Important observed difference:

- Codex App's own local worktrees live under `~/.codex/worktrees/<short-id>/<repo-name>`.
- Operator's worktrees lived under `~/Library/Application Support/Operator/worktrees/<repo-id>/<attempt-id>`.

## Inference

Codex App sidebar grouping appears to depend on more than Git common dir.

Likely inputs include:

- The saved thread cwd.
- Whether the cwd is in a Codex-managed worktree location.
- Git metadata such as origin URL, branch, and SHA.
- Possibly internal source fields such as `source` or `thread_source`.

This was not proven from source code. It was inferred by comparing persisted
session metadata, app-server behavior, and Codex App UI behavior.

The practical conclusion is stronger than the exact mechanism:

- `thread/start.cwd` must be the run worktree, not the source repo.
- Operator-created worktrees should mimic Codex App's local worktree layout.
- Git metadata should be sent to Codex App when available.

## Implemented Decision

Operator now starts Codex threads in the run worktree and creates app-visible
worktrees under Codex's worktree root:

```text
~/.codex/worktrees/<short-attempt-id>/<repo-name>
```

The default reusable `WorktreePreparer` can still be given any worktree root for
tests or future callers, but the desktop app injects:

```text
OperatorAppBootstrap.codexWorktreesURL()
```

which resolves to:

```text
~/.codex/worktrees
```

Operator also sends git metadata after `thread/start` and before `turn/start`:

```text
thread/metadata/update
  threadId
  gitInfo.sha
  gitInfo.branch
  gitInfo.originUrl
```

For repositories without an `origin` remote, Operator uses the local source
repository path as the origin-like identifier. This preserves useful grouping
metadata for local-only projects.

## App-Server Behavior Notes

Observed behavior:

- `thread/start.cwd` determines the saved thread cwd.
- `turn/start.cwd` does not rewrite the saved thread cwd.
- `thread/list` cwd filtering is exact-path based.
- `thread/metadata/update` accepts and persists `gitInfo`, but `gitInfo` alone
  did not make an Operator worktree under Application Support appear in the
  source repo sidebar group.
- Thread deep links can open a thread even when it is not visible in the
  expected sidebar group.

## Design Rules For Future Changes

Keep these rules unless Codex App exposes an explicit project/grouping API:

1. Start `thread/start` with the actual run worktree as cwd.
2. Start `turn/start` with the same run worktree as cwd.
3. Do not use the source repository path as `thread/start.cwd` just to influence
   sidebar grouping.
4. Keep Operator-generated worktrees outside the source repo.
5. Prefer the Codex App worktree layout for user-visible Codex threads:
   `~/.codex/worktrees/<short-id>/<repo-name>`.
6. Send git metadata with `thread/metadata/update` when available.
7. Treat Codex App sidebar grouping as an observed integration behavior, not a
   stable public contract.

## Regression Checks

When changing this area, verify all of the following manually:

1. Send a new Operator task.
2. Ask Codex in that thread where it is working.
3. Confirm the reported cwd is under `~/.codex/worktrees/.../<repo-name>`.
4. Open the same thread from Operator's "Open in Codex App".
5. Continue the thread in Codex App.
6. Confirm the continued turn still runs in the worktree.
7. Confirm the thread appears under the expected repository in Codex App's
   sidebar.

Automated tests should cover:

- Worktree creation is detached.
- Worktree creation uses the configured worktree root.
- The Codex-compatible worktree path shape is `<short-id>/<repo-name>`.
- `thread/start.cwd` and `turn/start.cwd` are both the run worktree.
- `thread/metadata/update` is sent before `turn/start`.

## Related Code

- `desktop/Sources/OperatorDesktop/Repositories/WorktreePreparer.swift`
- `desktop/Sources/OperatorDesktop/Repositories/CodexTriggerService.swift`
- `desktop/Sources/OperatorDesktop/Repositories/CodexAppServerStdioClient.swift`
- `desktop/Sources/OperatorDesktop/Persistence/OperatorAppBootstrap.swift`
- `desktop/Sources/OperatorApp/OperatorApp.swift`

## Related Commit

```text
5f4cc87 fix: keep operator threads in codex worktrees
```

## External Reference

- OpenAI Help Center, "Using Codex with your ChatGPT plan": describes Codex App
  as offering built-in worktree support. It does not document the app-server or
  sidebar grouping details captured here.
  https://help.openai.com/en/articles/11369540-getting-started-with-codex
