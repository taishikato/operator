import Foundation
import Testing
import CursorOperatorCore

// Integration tests against the real operator-cli binary. These cover
// ArgumentParser parsing, --json error envelopes, and documented exit codes as
// an agent sees them.

@Test func jsonSuccessOutputIsParseableJSONOnStdout() throws {
    let result = try runCLI(["repo", "list", "--json"])

    #expect(result.exitCode == 0)
    let object = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8))
    #expect(object as? [Any] != nil)
    #expect(result.stderr.isEmpty)
}

@Test func helpUsesOperatorCommandName() throws {
    let result = try runCLI(["--help"])

    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("operator <subcommand>"))
    #expect(!result.stdout.contains("cursor-operator <subcommand>"))
}

@Test func jsonDomainErrorUsesTheEnvelopeAndDocumentedExitCode() throws {
    let result = try runCLI(["task", "show", UUID().uuidString, "--json"])

    #expect(result.exitCode == 2)
    #expect(try errorEnvelope(in: result.stdout).code == "notFound")
}

@Test func jsonUsageErrorFromValidationUsesTheEnvelopeOnStdout() throws {
    let result = try runCLI([
        "task", "add", "--repo", "r", "--title", "t",
        "--prompt", "a", "--prompt-file", "b", "--json"
    ])

    #expect(result.exitCode == 64)
    let envelope = try errorEnvelope(in: result.stdout)
    #expect(envelope.code == "usage")
    #expect(envelope.message.contains("exactly one of"))
}

@Test func jsonUsageErrorFromUnknownOptionUsesTheEnvelope() throws {
    let result = try runCLI(["task", "list", "--bogus", "--json"])

    #expect(result.exitCode == 64)
    #expect(try errorEnvelope(in: result.stdout).code == "usage")
}

@Test func taskAddAutoSendParsesAndReportsMissingCredentialsAfterCreatingTask() throws {
    let scratchDirectory = FileManager.default.temporaryDirectory
        .appending(path: "CursorOperatorCLIIntegrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
    let databaseURL = scratchDirectory.appending(path: "operator.sqlite")
    let store = try CursorOperatorStore(databaseURL: databaseURL)
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )

    let result = try runCLI([
        "task", "add",
        "--repo", repository.id.uuidString,
        "--title", "Auto send",
        "--prompt", "Prompt",
        "--auto-send",
        "--json"
    ], databaseURL: databaseURL)

    #expect(result.exitCode == 4)
    #expect(try errorEnvelope(in: result.stdout).code == "cursorUnavailable")
    #expect(try store.tasks().first?.title == "Auto send")
    #expect(try store.tasks().first?.status == .ready)
}

@Test func taskAddRejectsUnsupportedHarnessClaudeCode() throws {
    let scratchDirectory = FileManager.default.temporaryDirectory
        .appending(path: "CursorOperatorCLIIntegrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
    let databaseURL = scratchDirectory.appending(path: "operator.sqlite")
    let store = try CursorOperatorStore(databaseURL: databaseURL)
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )

    let result = try runCLI([
        "task", "add",
        "--repo", repository.id.uuidString,
        "--title", "Claude Code task",
        "--prompt", "Prompt",
        "--harness", "claude-code",
        "--json"
    ], databaseURL: databaseURL)

    #expect(result.exitCode == 64)
    let envelope = try errorEnvelope(in: result.stdout)
    #expect(envelope.code == "usage")
    #expect(envelope.message.contains("cursor or codex"))
    #expect(try store.tasks().isEmpty)
}

@Test func taskAddRejectsAutoCreatePRForCodexTasks() throws {
    let scratchDirectory = FileManager.default.temporaryDirectory
        .appending(path: "CursorOperatorCLIIntegrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
    let databaseURL = scratchDirectory.appending(path: "operator.sqlite")
    let store = try CursorOperatorStore(databaseURL: databaseURL)
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )

    let result = try runCLI([
        "task", "add",
        "--repo", repository.id.uuidString,
        "--title", "Codex PR task",
        "--prompt", "Prompt",
        "--harness", "codex",
        "--auto-create-pr",
        "--json"
    ], databaseURL: databaseURL)

    #expect(result.exitCode == 64)
    let envelope = try errorEnvelope(in: result.stdout)
    #expect(envelope.code == "usage")
    #expect(envelope.message.contains("auto-create-pr"))
    #expect(try store.tasks().isEmpty)
}

@Test func taskAddCanCreateCodexTasksFromTheOperatorBinary() throws {
    let scratchDirectory = FileManager.default.temporaryDirectory
        .appending(path: "CursorOperatorCLIIntegrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
    let databaseURL = scratchDirectory.appending(path: "operator.sqlite")
    let store = try CursorOperatorStore(databaseURL: databaseURL)
    let repository = try store.createRepository(
        name: "operator",
        localPath: "/tmp/operator",
        githubURL: URL(string: "https://github.com/example/operator")!,
        defaultBranch: "main"
    )

    let result = try runCLI([
        "task", "add",
        "--repo", repository.id.uuidString,
        "--title", "Codex task",
        "--prompt", "Prompt",
        "--harness", "codex",
        "--json"
    ], databaseURL: databaseURL)

    #expect(result.exitCode == 0)
    let task = try #require(try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
    #expect(task["harness"] as? String == "codex")
    #expect(try store.tasks().first?.harness == .codex)
}

@Test func usageErrorWithoutJSONKeepsThePlainTextContract() throws {
    let result = try runCLI(["task", "list", "--bogus"])

    #expect(result.exitCode == 64)
    #expect(result.stdout.isEmpty)
    #expect(result.stderr.contains("--bogus"))
}

private struct CLIResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private struct ErrorEnvelope {
    let code: String
    let message: String
}

private func errorEnvelope(in stdout: String) throws -> ErrorEnvelope {
    let object = try #require(
        try JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any],
        "stdout is not a JSON object: \(stdout)"
    )
    let error = try #require(object["error"] as? [String: Any])
    return ErrorEnvelope(
        code: try #require(error["code"] as? String),
        message: try #require(error["message"] as? String)
    )
}

private func runCLI(
    _ arguments: [String],
    databaseURL: URL? = nil,
    extraEnvironment: [String: String] = [:]
) throws -> CLIResult {
    let databaseURL = try databaseURL ?? temporaryDatabaseURL()

    let process = Process()
    process.executableURL = cliBinaryURL()
    process.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    environment["CURSOR_OPERATOR_DB"] = databaseURL.path
    environment["CURSOR_OPERATOR_IGNORE_CREDENTIALS"] = "1"
    environment.removeValue(forKey: "CURSOR_API_KEY")
    for (key, value) in extraEnvironment {
        environment[key] = value
    }
    process.environment = environment

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return CLIResult(
        exitCode: process.terminationStatus,
        stdout: String(decoding: stdoutData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines),
        stderr: String(decoding: stderrData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    )
}

private func temporaryDatabaseURL() throws -> URL {
    let scratchDirectory = FileManager.default.temporaryDirectory
        .appending(path: "CursorOperatorCLIIntegrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
    return scratchDirectory.appending(path: "operator.sqlite")
}

private final class TestBundleLocator {}

private func cliBinaryURL() -> URL {
    var directory = Bundle(for: TestBundleLocator.self).bundleURL.deletingLastPathComponent()
    let fileManager = FileManager.default
    while directory.path != "/" {
        let candidate = directory.appending(path: "operator-cli")
        if fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        directory = directory.deletingLastPathComponent()
    }
    fatalError("Could not locate the operator-cli binary in the build products directory.")
}
