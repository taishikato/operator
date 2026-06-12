import Foundation
import Testing

// Integration tests against the real operator-cli binary. They cover the
// CLI surface the unit tests cannot: ArgumentParser parsing, the --json
// error envelope, and the documented exit codes as seen by an agent.

// MARK: - success path

@Test func jsonSuccessOutputIsParseableJSONOnStdout() throws {
    let result = try runCLI(["repo", "list", "--json"])

    #expect(result.exitCode == 0)
    let object = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8))
    #expect(object as? [Any] != nil)
    #expect(result.stderr.isEmpty)
}

// MARK: - domain errors

@Test func jsonDomainErrorUsesTheEnvelopeAndDocumentedExitCode() throws {
    let result = try runCLI(["task", "show", UUID().uuidString, "--json"])

    #expect(result.exitCode == 2)
    #expect(try errorEnvelope(in: result.stdout).code == "notFound")
}

// MARK: - usage errors (ArgumentParser-level, bypassing subcommand run())

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

@Test func sendRejectsNonPositiveTimeoutAsUsageError() throws {
    let result = try runCLI(["task", "send", UUID().uuidString, "--timeout", "0", "--json"])

    #expect(result.exitCode == 64)
    let envelope = try errorEnvelope(in: result.stdout)
    #expect(envelope.code == "usage")
    #expect(envelope.message.contains("--timeout"))
}

@Test func usageErrorWithoutJSONKeepsThePlainTextContract() throws {
    let result = try runCLI(["task", "list", "--bogus"])

    #expect(result.exitCode == 64)
    #expect(result.stdout.isEmpty)
    #expect(result.stderr.contains("--bogus"))
}

// MARK: - helpers

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

private func runCLI(_ arguments: [String]) throws -> CLIResult {
    let scratchDirectory = FileManager.default.temporaryDirectory
        .appending(path: "OperatorCLIIntegrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)

    let process = Process()
    process.executableURL = cliBinaryURL()
    process.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    environment["OPERATOR_DB"] = scratchDirectory.appending(path: "operator.sqlite").path
    environment["OPERATOR_DATA_DIR"] = scratchDirectory.path
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

private final class TestBundleLocator {}

/// The build products directory containing operator-cli; swift test builds
/// the executable because this target depends on it. Walks up from this test
/// bundle's location to the products directory.
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
