Status: ready-for-human

# Open in Cursor and manual completion flow

## Parent

.scratch/cursor-operator/PRD.md

## What to build

Finish the post-send workflow. Running, Done, and Archived tasks with a Cursor run reference should expose Open in Cursor, which opens the saved Cursor Cloud Agent web URL in the default browser. Users should be able to manually mark Running tasks Done and archive sent work without Operator claiming that Cursor succeeded.

This slice should make Cursor the continuation surface while keeping Operator's Done state explicitly manual.

## Acceptance criteria

- [x] Running tasks with a saved Cursor URL expose Open in Cursor.
- [x] Done and Archived sent tasks also expose Open in Cursor.
- [x] Open in Cursor opens the saved web URL through an injectable opener so tests do not launch a real browser.
- [x] If no direct URL exists, the app provides a fallback to copy the run id or open a Cursor Cloud Agent dashboard destination.
- [x] Running tasks can be manually marked Done.
- [x] Done does not trigger Cursor status polling or imply successful code output.
- [x] Cursor Desktop deep links, webhooks, and run status polling remain out of scope.
- [x] Tests cover URL opening, fallback behavior, manual Done, archive, and absence of automatic status polling.

## Blocked by

- .scratch/cursor-operator/issues/07-send-task-to-cursor-with-fake-runtime.md
- .scratch/cursor-operator/issues/08-real-cursor-cloud-agent-rest-client.md
