Status: ready-for-human

# Real Cursor Cloud Agent REST client

## Parent

.scratch/cursor-operator/PRD.md

## What to build

Replace the fake runtime path with the real Cursor Cloud Agent client selected by the REST API schema spike. The real client should start Cursor Cloud Agent from the saved GitHub repository URL and default branch, pass the fixed model and auto-create PR setting as API fields, send the prompt exactly as written, and map the response into the stored Cursor run reference.

This slice should preserve all send-flow behavior proven by the fake runtime: Ready to Running on success, Ready with sanitized error on failure, retry after failure, and no rerun after success.

## Acceptance criteria

- [x] The send flow can use the real Cursor Cloud Agent runtime client behind the same narrow interface as the fake client.
- [x] The real request sends prompt text, repository URL, starting ref, `composer-2.5`, and auto-create PR according to the schema spike.
- [x] Successful responses store Cursor agent id and open URL.
- [x] Auth failure, validation failure, malformed response, and network failure map to short sanitized send failures.
- [x] The app does not store raw HTTP bodies, API keys, event streams, transcripts, diffs, commits, or PR status.
- [x] Tests use fake HTTP transport or fixtures rather than live Cursor calls.
- [x] If the spike selected a Node SDK helper fallback, the helper is invoked through the same runtime interface and the distribution/runtime tradeoff is documented.

Note: Issue 06 selected the REST API path for the MVP, so no Node SDK helper fallback is included in this slice.

## Blocked by

- .scratch/cursor-operator/issues/06-cursor-cloud-agent-rest-api-schema-spike.md
- .scratch/cursor-operator/issues/07-send-task-to-cursor-with-fake-runtime.md
