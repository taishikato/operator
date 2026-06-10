# Plan 002: Ship a versioned, downloadable DMG release channel

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat a8c3955..HEAD -- codex_operator/script codex_operator/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `a8c3955`, 2026-06-10

## Why this matters

The README promises "A downloadable `.dmg` build is planned for the near
future" (`codex_operator/README.md:40`), and `script/package_release.sh`
already builds a DMG with optional codesigning and notarization — but the
bundle has no version number at all (no `CFBundleShortVersionString` /
`CFBundleVersion` in the generated Info.plist), the DMG filename is always
`Operator.dmg`, and there is no release channel (no `.github/workflows/`, no
GitHub Releases). Users cannot tell which build they are running and there is
nothing to download. This plan adds version stamping and a documented,
repeatable `gh release` publishing flow. It deliberately stays local-machine
based: CI release builds are deferred (the app targets macOS 26 and GitHub
runner support for the matching toolchain is unverified).

## Current state

- `codex_operator/script/package_release.sh` — builds
  `dist/release/staging/Operator.app`, writes an Info.plist from a heredoc,
  optionally signs (when `CODESIGN_IDENTITY` is set) and notarizes (when
  `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD` are set), then
  creates `dist/release/Operator.dmg` and a `.sha256` next to it.
  Top of the script (lines 4–6, 20):

  ```bash
  APP_NAME="Operator"
  BUNDLE_ID="com.focus.operator.desktop"
  MIN_SYSTEM_VERSION="26.0"
  ...
  DMG_PATH="$RELEASE_DIR/$APP_NAME.dmg"
  ```

  The Info.plist heredoc (around lines 63–86) contains `CFBundleIconFile`,
  `CFBundleExecutable`, `CFBundleIdentifier`, `CFBundleName`,
  `CFBundlePackageType`, `LSMinimumSystemVersion`, `NSPrincipalClass` — and
  no version keys.

- `codex_operator/README.md:40` — "A downloadable `.dmg` build is planned
  for the near future."

- `dist/` is partially committed/ignored — check `.gitignore` behavior before
  assuming; release artifacts must NOT be committed.

- No `.github/workflows/` directory exists in the repo.

- Shell convention: existing scripts use `set -euo pipefail` and a
  `require_command` helper — match them.

## Commands you will need

| Purpose        | Command (from `codex_operator/`)            | Expected on success            |
|----------------|---------------------------------------------|--------------------------------|
| Tests          | `swift test`                                | exit 0 (126+ tests)            |
| Package        | `script/package_release.sh`                 | exit 0, DMG + .sha256 in `dist/release/` |
| Script lint    | `bash -n script/package_release.sh`         | exit 0                         |
| Release (new)  | `gh release create vX.Y.Z ...`              | release URL printed            |

(`swift test` verified passing at planning time. `gh` is assumed available;
verify with `gh auth status` before step 3.)

## Scope

**In scope** (the only files you should modify/create):
- `codex_operator/script/package_release.sh`
- `codex_operator/README.md`
- `docs/releasing.md` (create)

**Out of scope** (do NOT touch, even though they look related):
- `.github/workflows/` — CI release automation is explicitly deferred.
- `script/build_and_run.sh` — dev loop, not release.
- Sparkle / in-app auto-update — separate future decision.
- Committing anything under `dist/` — artifacts stay untracked.
- Secret values: refer to `CODESIGN_IDENTITY`, `APPLE_ID`, `APPLE_TEAM_ID`,
  `APPLE_APP_SPECIFIC_PASSWORD` by name only; never write values into any
  file.

## Git workflow

- Branch: `advisor/002-versioned-dmg-release`
- Commit style: conventional, e.g. `chore: version release dmg artifacts`
  (matches `git log`, e.g. `chore: add release packaging script`).
- Do NOT push, tag, or open a PR unless the operator instructed it. Step 3's
  actual `gh release create` run is the operator's call — the deliverable is
  the script support + documented procedure, verified up to DMG creation.
- Repo rule (CLAUDE.md): PRs are merged without squashing — do not squash.

## Steps

### Step 1: Add version stamping to `package_release.sh`

- Accept a version as `$1` or `$VERSION` env var; default to `0.0.0-dev` so
  the script keeps working with no arguments.
- Validate the version against `^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$`;
  exit 1 with a clear message otherwise.
- Add to the Info.plist heredoc:
  `CFBundleShortVersionString` = the version, and `CFBundleVersion` = the
  version (a monotonically increasing build number is overkill for now).
- Name the artifact `Operator-<version>.dmg` (update `DMG_PATH`); keep the
  `.sha256` sibling naming.

**Verify**: `bash -n script/package_release.sh` → exit 0. Then
`VERSION=0.1.0 script/package_release.sh` →
`dist/release/Operator-0.1.0.dmg` and `.sha256` exist, and
`/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" dist/release/staging/Operator.app/Contents/Info.plist`
prints `0.1.0`.

### Step 2: Write `docs/releasing.md`

Document the end-to-end release procedure for a human or agent:

1. Preconditions: clean main, `swift test` green, `gh auth status` OK.
2. Signing/notarization env vars (names only) and what happens when each is
   absent (unsigned DMG warning / notarization skipped — quote the script's
   actual stderr messages).
3. Gatekeeper caveat for unsigned builds (right-click → Open) — this is the
   realistic state until signing credentials are configured.
4. The release commands:
   ```bash
   cd codex_operator
   VERSION=X.Y.Z script/package_release.sh
   gh release create vX.Y.Z \
     dist/release/Operator-X.Y.Z.dmg \
     dist/release/Operator-X.Y.Z.dmg.sha256 \
     --title "Operator X.Y.Z" --notes "<highlights>"
   ```
5. A note that tagging/publishing is operator-initiated, and that CI
   automation is deferred (with one line on why: unverified macOS 26
   toolchain availability on hosted runners).

**Verify**: file exists; every command in it is copy-pasteable (no
placeholders other than `X.Y.Z` and `<highlights>`).

### Step 3: Update the README

In `codex_operator/README.md`, replace the "planned for the near future"
line (line 40) with a short "Install" subsection: download the latest DMG
from GitHub Releases (link to `https://github.com/taishikato/operator/releases`),
plus the unsigned-build Gatekeeper note, plus a pointer to
`docs/releasing.md` for maintainers.

**Verify**: `grep -n "planned for the near future" codex_operator/README.md`
→ no matches; `grep -n "releases" codex_operator/README.md` → ≥1 match.

## Test plan

This plan is script + docs; no Swift tests change. Gates:
- `swift test` still exits 0 (no source impact expected — this confirms it).
- The step 1 packaging run on this machine succeeds and the plist version
  check passes.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `VERSION=0.1.0 script/package_release.sh` exits 0 and produces `dist/release/Operator-0.1.0.dmg`
- [ ] PlistBuddy prints `0.1.0` for `CFBundleShortVersionString` (command in step 1)
- [ ] `script/package_release.sh` with no args still exits 0 (default version)
- [ ] `docs/releasing.md` exists and contains `gh release create`
- [ ] `grep -rn "planned for the near future" codex_operator/README.md` returns nothing
- [ ] `git status` shows nothing under `dist/` staged or tracked-and-modified
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The Info.plist heredoc in the script doesn't match the keys listed in
  "Current state" (script has drifted).
- `script/package_release.sh` fails at planning-state baseline (run it once
  unmodified first; if it already fails, report — don't fix the build).
- `dist/` turns out to be tracked in git such that artifacts would be
  committed — report instead of editing `.gitignore` (out of scope).
- You are tempted to add a GitHub Actions workflow — explicitly deferred.

## Maintenance notes

- When signing credentials are configured, `docs/releasing.md` should be the
  only place that needs an update (env var setup section).
- Follow-up explicitly deferred: CI release workflow on tag push (needs a
  runner image check for the macOS 26 toolchain) and in-app update checks.
- Reviewer should scrutinize: version regex, and that no-arg invocation
  still works for local packaging.
