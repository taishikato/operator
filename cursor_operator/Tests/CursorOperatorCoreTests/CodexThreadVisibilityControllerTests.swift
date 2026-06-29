import Foundation
import Testing
@testable import CursorOperatorCore

@Test func codexThreadVisibilityControllerArchivesAndUnarchivesWithConfiguredBinary() async throws {
    let binaryURL = URL(filePath: "/opt/homebrew/bin/codex")
    let runner = RecordingCodexCommandRunner(results: [true, true])
    let controller = CodexCLIThreadVisibilityController(
        settings: StaticVisibilityCodexBinarySettingsProvider(binaryURL: binaryURL),
        commandRunner: runner,
        timing: .init(
            hideAttemptInterval: .milliseconds(1),
            hideTimeout: .milliseconds(20),
            revealAttempts: 1,
            revealRetryInterval: .milliseconds(1)
        )
    )

    let hidden = await controller.hideThread(id: "thread-123")
    let revealed = await controller.revealThread(id: "thread-123")

    #expect(hidden)
    #expect(revealed)
    #expect(runner.commands == [
        .init(binaryURL: binaryURL, arguments: ["archive", "thread-123"]),
        .init(binaryURL: binaryURL, arguments: ["unarchive", "thread-123"])
    ])
}

private final class RecordingCodexCommandRunner: CodexCommandRunning, @unchecked Sendable {
    struct Command: Equatable {
        let binaryURL: URL
        let arguments: [String]
    }

    private let lock = NSLock()
    private var results: [Bool]
    private var commandsValue: [Command] = []

    var commands: [Command] {
        lock.withLock { commandsValue }
    }

    init(results: [Bool]) {
        self.results = results
    }

    func runCodex(binaryURL: URL, arguments: [String]) async -> Bool {
        lock.withLock {
            commandsValue.append(Command(binaryURL: binaryURL, arguments: arguments))
            return results.removeFirst()
        }
    }
}

private struct StaticVisibilityCodexBinarySettingsProvider: CodexBinarySettingsProviding {
    let binaryURL: URL?

    func configuration() throws -> CodexBinaryConfiguration {
        CodexBinaryConfiguration(detectedBinaryURL: binaryURL, overrideBinaryURL: nil)
    }
}
