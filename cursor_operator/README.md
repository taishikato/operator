# Operator

Operator is a native macOS SwiftUI Kanban UI app and companion CLI for coding-agent tasks.
This package currently keeps the Cursor Cloud Agent runtime inside `cursor_operator`.

[Download the latest release](https://github.com/taishikato/operator/releases)

<img width="2880" height="1800" alt="CleanShot 2026-06-21 at 22 07 39@2x" src="https://github.com/user-attachments/assets/3a8d0494-5aad-4f15-8931-bdb31939fd8e" />


## Development

```bash
swift build
swift test
./script/build_and_run.sh
```

Operator stores local app data under the `Operator` Application Support directory and uses the `com.focus.operator` bundle identity.
Old Cursor Operator and Codex Operator local databases are not migrated.
