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

For Developer ID signing and notarization, see [docs/distribution.md](docs/distribution.md).
