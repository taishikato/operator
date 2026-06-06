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

private struct StubCodexStatusRunner: CodexStatusRunning {
    let result: Result<CodexStatusRunnerSuccess, CodexStatusRunnerFailure>

    func runCodexStatus(binaryURL: URL) async -> Result<CodexStatusRunnerSuccess, CodexStatusRunnerFailure> {
        result
    }
}
