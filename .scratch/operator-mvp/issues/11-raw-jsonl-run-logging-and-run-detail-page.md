Status: ready-for-human
Type: AFK

# Raw JSONL run logging and run detail page

## Parent

.scratch/operator-mvp/PRD.md

## What to build

Persist complete redacted run logs as JSONL and make them viewable from the UI. The log should include Cursor SDK events and Operator events, be addressed by relative log key, and support a dedicated page that is useful for debugging without adding custom search in the MVP.

## Acceptance criteria

- [x] Each run records a relative raw log key.
- [x] Cursor SDK events and Operator events append as JSONL.
- [x] Minimal secret redaction is applied before events are written.
- [x] Task drawer shows run summary and a link to the raw log page.
- [x] Raw log page displays the log in chronological order.
- [x] Raw log page supports copy and download.
- [x] Running logs refresh through polling only while the run is active.
- [x] Tests cover JSONL append behavior, relative log keys, and redaction behavior.

## Blocked by

- .scratch/operator-mvp/issues/10-cursor-sdk-run-orchestration-tracer.md

## Implementation result

Implemented raw JSONL run logs with relative `runs/{runId}.jsonl` keys stored on `runs.raw_log_key`, redacted JSONL append for Operator and Cursor SDK events, latest run summaries in the Task drawer, and a dedicated `/runs/[runId]` raw log page with copy/download and active-run polling through `/api/runs/[runId]`.

Verification:

- `pnpm test` passed.
- `pnpm typecheck` passed.
- `pnpm lint` passed.
- `pnpm build` passed with the existing Turbopack NFT warning for `next.config.ts` import tracing through the Project detection route.
