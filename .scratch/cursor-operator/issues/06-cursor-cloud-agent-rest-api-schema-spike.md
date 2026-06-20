Status: ready-for-human

# Cursor Cloud Agent REST API schema spike

## Parent

.scratch/cursor-operator/PRD.md

## What to build

Determine and document the Cursor Cloud Agent REST contract that Cursor Operator should use. This is an AFK spike: use public Cursor documentation, SDK examples, installed package metadata if available, and mocked fixtures to produce an implementation-ready contract. Do not require a human's live Cursor account or API key to complete the ticket.

The output should establish the endpoint path, auth header, request fields, response fields, error shape, agent id field, open URL field, starting ref field, model field, and auto-create PR field. If any field cannot be verified without live access, document the uncertainty and the fallback condition for using a Node helper with the Cursor SDK.

## Acceptance criteria

- [x] The preferred Swift REST request contract is documented in implementation-facing notes.
- [x] The contract covers auth, prompt text, GitHub repository URL, starting ref, fixed `composer-2.5` model, and auto-create PR.
- [x] The expected success response mapping covers Cursor agent id and open URL.
- [x] The expected error response mapping covers auth failure, validation failure, malformed response, and network failure.
- [x] Fake HTTP fixtures or tests encode the selected request and response shapes.
- [x] Any unverifiable live-only assumptions are explicitly listed with a fallback condition.
- [x] The spike states whether Swift REST remains the implementation path or a Node SDK helper is required.

## Blocked by

- .scratch/cursor-operator/issues/05-cursor-credential-settings-with-keychain-storage.md
