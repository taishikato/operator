# Cursor Operator

Cursor Operator is a native macOS SwiftUI app for preparing local Cursor Cloud Agent tasks.

## Development

```bash
swift build
swift test
./script/build_and_run.sh
```

Cursor Operator stores local app data under the `Cursor Operator` Application Support directory and uses the `com.focus.cursor-operator` bundle identity.

## Distribution

Build a release DMG:

```bash
./script/package_distribution.sh dmg
```

The DMG installs `CursorOperator.app`. After launching the app, open Settings
and use the Agent Support section to install or repair the `cursor-operator`
CLI and agent skills. The CLI is linked into `~/.local/bin`, and skills are
linked into Codex, Cursor, and Claude skill directories.

For Developer ID signing and notarization, see [docs/distribution.md](docs/distribution.md).
