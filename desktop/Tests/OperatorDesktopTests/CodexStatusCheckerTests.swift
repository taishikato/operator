import Foundation
import Testing
@testable import OperatorDesktop

@Test func codexStatusStartsAsNotChecked() {
    #expect(CodexStatus.notChecked.title == "Not checked")
    #expect(CodexStatus.notChecked.message == "Codex status has not been checked yet.")
}

@Test func codexStatusCheckerReportsNotFoundWhenNoBinaryPathExists() async {
    let checker = CodexStatusChecker(runner: StubCodexStatusRunner(result: .success(.ready)))

    let status = await checker.checkStatus(binaryURL: nil)

    #expect(status == .notFound)
    #expect(status.title == "Not found")
}

@Test func codexStatusCheckerReportsReadyWhenRunnerSucceeds() async {
    let checker = CodexStatusChecker(runner: StubCodexStatusRunner(result: .success(.ready)))
    let binaryURL = URL(filePath: "/opt/homebrew/bin/codex")

    let status = await checker.checkStatus(binaryURL: binaryURL)

    #expect(status == .ready(binaryURL))
    #expect(status.title == "Ready")
}

@Test func codexStatusCheckerReportsUnavailableWhenRunnerFindsAuthenticationFailure() async {
    let checker = CodexStatusChecker(
        runner: StubCodexStatusRunner(result: .failure(.notAuthenticatedOrUnavailable("Run codex login.")))
    )

    let status = await checker.checkStatus(binaryURL: URL(filePath: "/opt/homebrew/bin/codex"))

    #expect(status == .notAuthenticatedOrUnavailable("Run codex login."))
    #expect(status.title == "Not authenticated or unavailable")
    #expect(status.message == "Run codex login.")
}

@Test func processCodexStatusRunnerInvokesLoginStatusSubcommand() async throws {
    let directory = try temporaryCodexStatusTestDirectory()
    let recordURL = directory.appending(path: "arguments.txt")
    let fakeBinaryURL = directory.appending(path: "fake-codex")
    try writeExecutableScript(
        """
        #!/bin/sh
        printf '%s\\n' "$@" > "\(recordURL.path)"
        exit 0
        """,
        to: fakeBinaryURL
    )

    let result = await ProcessCodexStatusRunner().runCodexStatus(binaryURL: fakeBinaryURL)

    #expect(result == .success(.ready))
    let recordedArguments = try String(contentsOf: recordURL, encoding: .utf8)
        .split(whereSeparator: \.isNewline)
        .map(String.init)
    #expect(recordedArguments == ["login", "status"])
}

private struct StubCodexStatusRunner: CodexStatusRunning {
    let result: Result<CodexStatusRunnerSuccess, CodexStatusRunnerFailure>

    func runCodexStatus(binaryURL: URL) async -> Result<CodexStatusRunnerSuccess, CodexStatusRunnerFailure> {
        result
    }
}

private func temporaryCodexStatusTestDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "CodexStatusCheckerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func writeExecutableScript(_ body: String, to url: URL) throws {
    try body.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}
