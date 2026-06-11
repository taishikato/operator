import Foundation
import Testing
@testable import OperatorDesktop

@Test func threadVisibilityHideRetriesUntilArchiveSucceeds() async throws {
    let harness = try FakeCodexBinaryHarness(named: "VisibilityHideRetries")
    let controller = CodexCLIThreadVisibilityController(
        settings: harness.settings,
        timing: .init(
            hideAttemptInterval: .milliseconds(20),
            hideTimeout: .seconds(10)
        )
    )

    harness.allowArchiveAfterAttempts(3)
    let hidden = await controller.hideThread(id: "thread-vis-1")

    #expect(hidden)
    #expect(harness.invocations() == Array(repeating: "archive thread-vis-1", count: 3))
}

@Test func threadVisibilityHideStopsWhenCancelled() async throws {
    let harness = try FakeCodexBinaryHarness(named: "VisibilityHideCancel")
    let controller = CodexCLIThreadVisibilityController(
        settings: harness.settings,
        timing: .init(
            hideAttemptInterval: .milliseconds(20),
            hideTimeout: .seconds(10)
        )
    )

    let hideTask = Task {
        await controller.hideThread(id: "thread-vis-2")
    }
    try await Task.sleep(for: .milliseconds(100))
    hideTask.cancel()
    let hidden = await hideTask.value

    #expect(!hidden)
    let countAtCancel = harness.invocations().count
    try await Task.sleep(for: .milliseconds(150))
    #expect(harness.invocations().count == countAtCancel)
}

@Test func threadVisibilityHideTimesOutWhenRolloutNeverAppears() async throws {
    let harness = try FakeCodexBinaryHarness(named: "VisibilityHideTimeout")
    let controller = CodexCLIThreadVisibilityController(
        settings: harness.settings,
        timing: .init(
            hideAttemptInterval: .milliseconds(20),
            hideTimeout: .milliseconds(200)
        )
    )

    let hidden = await controller.hideThread(id: "thread-vis-3")

    #expect(!hidden)
}

@Test func threadVisibilityRevealRunsUnarchive() async throws {
    let harness = try FakeCodexBinaryHarness(named: "VisibilityReveal")
    let controller = CodexCLIThreadVisibilityController(settings: harness.settings)

    let revealed = await controller.revealThread(id: "thread-vis-4")

    #expect(revealed)
    #expect(harness.invocations() == ["unarchive thread-vis-4"])
}

@Test func threadVisibilityRevealRetriesBeforeGivingUp() async throws {
    let harness = try FakeCodexBinaryHarness(named: "VisibilityRevealRetry")
    harness.failUnarchive()
    let controller = CodexCLIThreadVisibilityController(
        settings: harness.settings,
        timing: .init(
            revealAttempts: 3,
            revealRetryInterval: .milliseconds(20)
        )
    )

    let revealed = await controller.revealThread(id: "thread-vis-5")

    #expect(!revealed)
    #expect(harness.invocations() == Array(repeating: "unarchive thread-vis-5", count: 3))
}

@Test func threadVisibilityReportsFailureWhenBinaryIsMissing() async throws {
    let controller = CodexCLIThreadVisibilityController(
        settings: MissingCodexBinarySettingsProvider()
    )

    #expect(await controller.hideThread(id: "thread-vis-6") == false)
    #expect(await controller.revealThread(id: "thread-vis-6") == false)
}

/// Stands in for the `codex` binary: `archive` succeeds only from the
/// configured attempt onwards (simulating the lazily created rollout file),
/// `unarchive` fails while `unarchive-fail` exists, and every invocation is
/// appended to a log.
private final class FakeCodexBinaryHarness: @unchecked Sendable {
    let settings: any CodexBinarySettingsProviding
    private let directory: URL

    init(named prefix: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let binaryURL = directory.appending(path: "codex")
        let script = """
        #!/bin/sh
        dir="$(dirname "$0")"
        echo "$@" >> "$dir/invocations.log"
        case "$1" in
        archive)
            required=$(cat "$dir/archive-succeeds-at" 2>/dev/null || echo 999999)
            count=$(grep -c '^archive' "$dir/invocations.log")
            [ "$count" -ge "$required" ] && exit 0
            exit 1
            ;;
        unarchive)
            [ -f "$dir/unarchive-fail" ] && exit 1
            exit 0
            ;;
        esac
        exit 0
        """
        try script.write(to: binaryURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)

        settings = StaticVisibilityBinarySettingsProvider(binaryURL: binaryURL)
    }

    func allowArchiveAfterAttempts(_ attempts: Int) {
        try? "\(attempts)".write(
            to: directory.appending(path: "archive-succeeds-at"),
            atomically: true,
            encoding: .utf8
        )
    }

    func failUnarchive() {
        FileManager.default.createFile(atPath: directory.appending(path: "unarchive-fail").path, contents: nil)
    }

    func invocations() -> [String] {
        guard let log = try? String(contentsOf: directory.appending(path: "invocations.log"), encoding: .utf8) else {
            return []
        }
        return log.split(whereSeparator: \.isNewline).map(String.init)
    }
}

private struct StaticVisibilityBinarySettingsProvider: CodexBinarySettingsProviding {
    let binaryURL: URL

    func configuration() throws -> CodexBinaryConfiguration {
        CodexBinaryConfiguration(detectedBinaryURL: binaryURL, overrideBinaryURL: nil)
    }
}

private struct MissingCodexBinarySettingsProvider: CodexBinarySettingsProviding {
    func configuration() throws -> CodexBinaryConfiguration {
        CodexBinaryConfiguration(detectedBinaryURL: nil, overrideBinaryURL: nil)
    }
}
