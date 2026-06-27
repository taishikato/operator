# Plan 005: Rebrand Cursor Operator foundation to Operator

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat c4ec8d4..HEAD -- cursor_operator/Package.swift cursor_operator/Sources/CursorOperatorCore/App cursor_operator/Sources/CursorOperatorApp cursor_operator/script cursor_operator/README.md README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: migration
- **Planned at**: commit `c4ec8d4`, 2026-06-27

## Why this matters

The PRD makes `cursor_operator` the implementation target, but the product name becomes Operator.
This plan creates the smallest vertical rebrand: app identity, app data path, package product names, scripts, docs, and tests agree that the app is Operator.
It deliberately does not migrate old Cursor Operator data because the PRD says old Cursor Operator and Codex Operator databases are ignored.

## Current state

- `cursor_operator/Package.swift` declares package and products named CursorOperator and `cursor-operator-cli`.
- `CursorOperatorAppSpec` centralizes display name, bundle id, Application Support directory, and database filename.
- `CursorOperatorAppBootstrap` builds the app data path from `CursorOperatorAppSpec`.
- `cursor_operator/script/build_and_run.sh` hardcodes app name, bundle id, CLI helper name, skill source, and Info.plist name.
- `cursor_operator/README.md` still describes Cursor Operator and says data lives under `Cursor Operator` Application Support.

Important excerpts:

```swift
// cursor_operator/Sources/CursorOperatorCore/App/CursorOperatorAppSpec.swift:7
public static let mvp = CursorOperatorAppSpec(
    displayName: "Cursor Operator",
    bundleIdentifier: "com.focus.cursor-operator",
    applicationSupportDirectoryName: "Cursor Operator",
    databaseFileName: "cursor-operator.sqlite"
)
```

```swift
// cursor_operator/Sources/CursorOperatorCore/App/CursorOperatorAppBootstrap.swift:32
public static func databaseURL(...) throws -> URL {
    try applicationDataURL(appSpec: appSpec, fileManager: fileManager, environment: environment)
        .appending(path: appSpec.databaseFileName)
}
```

```bash
# cursor_operator/script/build_and_run.sh:4
APP_NAME="CursorOperator"
BUNDLE_ID="com.focus.cursor-operator"
APP_CLI="$APP_HELPERS/cursor-operator-cli"
```

Repo conventions:

- Swift package, macOS 26.0 target, Swift 6.2.
- Tests live under `cursor_operator/Tests/*`.
- Existing tests use Swift Testing and temporary database URLs rather than real user data.
- UI visual changes must follow `cursor_operator/DESIGN.md`.
- Commit messages are English.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `cd cursor_operator && swift build` | exit 0 |
| Tests | `cd cursor_operator && swift test` | exit 0, all tests pass |
| Bundle smoke | `cd cursor_operator && ./script/build_and_run.sh --bundle` | exit 0 and `dist/Operator.app` exists |
| Git check | `git status --short` | only intended files modified |

## Scope

**In scope:**

- `cursor_operator/Package.swift`
- `cursor_operator/Sources/CursorOperatorCore/App/*`
- `cursor_operator/Sources/CursorOperatorApp/*`
- `cursor_operator/Sources/CursorOperatorCLI/*`
- `cursor_operator/Sources/CursorOperatorSmokeSupport/*`
- `cursor_operator/script/build_and_run.sh`
- `cursor_operator/script/package_distribution.sh`
- `cursor_operator/script/render_homebrew_cask.sh`
- `cursor_operator/script/install_cli.sh`
- `cursor_operator/script/install_skills.sh`
- `cursor_operator/README.md`
- `README.md`
- Related tests under `cursor_operator/Tests`

**Out of scope:**

- Adding Codex send behavior.
- Changing task lifecycle semantics.
- Migrating old Cursor Operator or Codex Operator databases.
- Renaming the top-level `cursor_operator/` directory.
- Removing provider-specific Cursor runtime names.

## Git workflow

- Branch: `codex/operator-rebrand-foundation`
- Commit message example: `feat: rebrand cursor operator foundation`
- Do not push unless instructed.

## Steps

### Step 1: Rename app spec values to Operator

Update the shared app spec so it uses:

- display name `Operator`
- bundle identifier for the new Operator app identity
- Application Support directory `Operator`
- database filename `operator.sqlite`

Keep a temporary compatibility environment override only if tests already rely on it.
If the override name changes, update tests and scripts together.

**Verify**: `cd cursor_operator && swift test --filter CursorOperatorAppBootstrapTests` -> exit 0.

### Step 2: Rename package products and executable targets where user-facing

Make the installed app product and CLI product line up with the rebrand.
The app product should be `Operator`.
The user command should be `operator`.
If macOS case-insensitive product collisions require the helper binary to stay distinct, use an internal product such as `operator-cli`, matching the Codex Operator precedent.

Do not rename provider-specific runtime modules in this plan.

**Verify**: `cd cursor_operator && swift build` -> exit 0.

### Step 3: Update bundle and install scripts

Update scripts so local bundling creates `dist/Operator.app`, Info.plist uses `Operator`, and the bundled CLI/helper path uses the new CLI helper name.
Update Install CLI to symlink `operator`, not `cursor-operator`.
Update Install Skills script to install an `operator` skill path if the skill exists, or leave a clear TODO in this plan's follow-up if the skill source is created by a later plan.

Do not preserve a `cursor-operator` compatibility alias.

**Verify**: `cd cursor_operator && ./script/build_and_run.sh --bundle` -> exit 0 and `test -d cursor_operator/dist/Operator.app` exits 0.

### Step 4: Update rebrand-facing tests and docs

Update tests that assert app name, bundle id, database path, package products, script output, or README copy.
Update root README and cursor app README to describe Operator as the integrated product direction.
Mention that old Cursor Operator and Codex Operator local databases are not migrated.

**Verify**: `cd cursor_operator && swift test` -> exit 0.

## Test plan

- Update `CursorOperatorAppBootstrapTests` or equivalent to assert `Operator/operator.sqlite`.
- Update build script tests to assert `Operator.app` and `operator` helper naming.
- Keep tests using temporary directories; do not touch real `~/Library/Application Support`.

## Done criteria

- [ ] `cd cursor_operator && swift build` exits 0.
- [ ] `cd cursor_operator && swift test` exits 0.
- [ ] `cd cursor_operator && ./script/build_and_run.sh --bundle` exits 0 and builds `dist/Operator.app`.
- [ ] App data path tests assert `Operator/operator.sqlite`.
- [ ] README mentions Operator and states old Cursor/Codex databases are not migrated.
- [ ] No `cursor-operator` CLI compatibility alias is added.
- [ ] `plans/README.md` status row for plan 005 is updated.

## STOP conditions

Stop and report if:

- Product renaming requires changing the top-level `cursor_operator/` directory.
- Build product collisions cannot be resolved with an internal helper name like `operator-cli`.
- Tests reveal that existing release scripts depend on old filenames in a way that requires a broader packaging redesign.
- Any step appears to require implementing Codex runtime behavior.

## Maintenance notes

Future plans build on the new Operator app identity.
Reviewers should scrutinize script changes because packaging bugs can make local builds look successful while producing stale app names or stale CLI helper paths.
Do not reintroduce a `cursor-operator` user command unless the maintainer explicitly reopens that product decision.
