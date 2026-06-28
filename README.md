# Operator

This repository contains native Operator clients for running coding agents against local Git repositories.

[Codex Operator](codex_operator/) (`codex_operator`) is a desktop app for Codex App. It is a Kanban board that triggers Codex directly, then opens the chat session in Codex App so you can continue working there.

[Operator](cursor_operator/) (`Operator.app` / `operator`) is the integrated product direction for preparing and sending coding-agent tasks from a native macOS SwiftUI board.
This foundation currently keeps the Cursor Cloud Agent runtime inside `cursor_operator` and does not migrate old Cursor Operator or Codex Operator local databases.

See the [Codex Operator README](codex_operator/README.md) for desktop app setup and usage details.

See the [Operator README](cursor_operator/README.md) for Cursor runtime setup and usage details.
