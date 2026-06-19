Status: ready-for-human

# Cursor credential settings with Keychain storage

## Parent

.scratch/cursor-operator/PRD.md

## What to build

Add Cursor API credential management to Settings. A user should be able to paste a Cursor API key, save it securely to macOS Keychain, see a masked present/missing status, validate through an injectable validation client, and delete the stored key. Development and tests may fall back to `CURSOR_API_KEY`, but SQLite and UserDefaults must never store the raw key.

This slice should make send readiness visible without requiring a real Cursor API call. The validation path should be testable with a fake client so AFK implementation does not depend on the developer's live Cursor account.

## Acceptance criteria

- [x] Settings exposes a Cursor API key section with save, masked status, validate, and delete actions.
- [x] Raw Cursor API keys are stored in macOS Keychain, not SQLite or UserDefaults.
- [x] `CURSOR_API_KEY` can be used as a development fallback when no Keychain value exists.
- [x] Key present/missing and validation success/failure are visible in Settings.
- [x] The credential store has an injectable abstraction so tests do not touch the developer's real Keychain entries.
- [x] Send readiness can detect missing credentials and present a clear blocked state.
- [x] Tests cover save/load/delete, environment fallback, masked status, validation result mapping, and missing credential behavior.

## Blocked by

- .scratch/cursor-operator/issues/01-app-shell-and-isolated-app-data.md
