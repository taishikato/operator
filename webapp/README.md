# Operator

Operator is a local-first Kanban control plane for running Cursor SDK agents against local Git repositories.

The MVP is source-checkout-first: install dependencies, build the Next.js app, then run the local production server with `operator start`.

## Prerequisites

- Node.js 20+
- pnpm 10+
- Atlas CLI on `PATH`
- Cursor API key in `CURSOR_API_KEY`
- GitHub CLI (`gh`) authenticated if you want to create draft PRs
- A separate local Git repository to use for dogfooding

Operator stores its local database and run logs in the OS app data directory, not inside managed Git repositories.

## Start Operator

From this directory:

```bash
pnpm install
pnpm build
CURSOR_API_KEY=your_cursor_api_key pnpm operator start
```

Operator starts on `http://127.0.0.1:3927` by default. The command fails if that port is already in use.

To open the browser automatically:

```bash
CURSOR_API_KEY=your_cursor_api_key pnpm operator start --open
```

Development remains separate:

```bash
pnpm dev
```

## Apply Database Schema Updates

First startup initializes a new local database automatically. Existing databases that need schema changes require an explicit apply:

```bash
pnpm operator db apply
```

Then start Operator again:

```bash
CURSOR_API_KEY=your_cursor_api_key pnpm operator start
```

## Dogfood Flow

1. Start Operator and open `http://127.0.0.1:3927`.
2. Add a Project by selecting or entering the path to a separate local Git repository.
3. Confirm the detected repository metadata and Project key.
4. Create a Task in Backlog with a title, body, and acceptance criteria.
5. Optionally set a Task model or reasoning override.
6. Move the Task to Ready.
7. Click Run Now, or use Run ready tasks from the board.
8. Wait for Operator to create or reuse the Task branch and run the Cursor SDK agent.
9. Inspect the Task after it moves to Review or Blocked.
10. Open the raw run log from the Task drawer if you need to debug the run.
11. For a Review Task, use Create PR to confirm the remote, branch, commit SHA, title, body, and draft status.
12. Submit the PR creation flow. Operator pushes the Task branch and creates a draft PR through local `gh` authentication.
13. Review the draft PR manually. Move the Task to Done only when you decide the work is complete.

## Scheduling

Project schedules are disabled by default. Enable them from Project settings, set the daily time/timezone, and choose the scheduled run limit.

Scheduled runs only happen while Operator is running. Missed schedules do not catch up automatically.

## Useful Checks

```bash
pnpm test
pnpm typecheck
pnpm lint
pnpm build
```

## Notes

- Cursor credentials come from `CURSOR_API_KEY`; Operator does not persist Cursor secrets.
- Draft PR creation uses local `gh` authentication; Operator does not persist GitHub tokens.
- Operator does not automatically pull, merge, rebase, or push except during the explicit Create PR flow.
- Successful agent runs require a new commit and a clean working tree.
- Failed or interrupted runs move Tasks to Blocked with a reason.
