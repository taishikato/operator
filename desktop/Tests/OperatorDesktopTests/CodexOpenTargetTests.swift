import Foundation
import Testing
@testable import OperatorDesktop

@Test func codexOpenTargetPrefersSavedThreadURL() throws {
    let run = successfulRun(
        worktreePath: "/tmp/operator-worktree",
        codexThreadURL: URL(string: "codex://thread/thread-1")
    )

    let target = try #require(CodexOpenTarget(run: run))

    #expect(target == .url(URL(string: "codex://thread/thread-1")!))
}

@Test func codexOpenTargetFallsBackToRunWorktreePath() throws {
    let run = successfulRun(
        worktreePath: "/tmp/operator worktree",
        codexThreadURL: nil
    )

    let target = try #require(CodexOpenTarget(run: run))

    #expect(target == .worktree(URL(filePath: "/tmp/operator worktree", directoryHint: .isDirectory)))
}

@Test func codexOpenTargetIsUnavailableForFailedRuns() {
    let run = OperatorRun(
        id: UUID(),
        taskID: UUID(),
        repositoryID: UUID(),
        status: .triggerFailed,
        worktreePath: "/tmp/operator-worktree",
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: nil,
        codexThreadURL: nil,
        errorMessage: "failed",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        completedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    #expect(CodexOpenTarget(run: run) == nil)
}

@Test func codexOpenCommandOpensDeepLinkDirectlyThroughOSOpen() {
    let target = CodexOpenTarget.url(URL(string: "codex://thread/thread-1")!)

    let command = CodexOpenCommand(target: target)

    #expect(command.executableURL == URL(filePath: "/usr/bin/open"))
    #expect(command.arguments == ["codex://thread/thread-1"])
}

@Test func codexOpenCommandOpensWorktreeWithCodexApplication() {
    let worktreeURL = URL(filePath: "/tmp/operator worktree", directoryHint: .isDirectory)

    let command = CodexOpenCommand(target: .worktree(worktreeURL))

    #expect(command.executableURL == URL(filePath: "/usr/bin/open"))
    #expect(command.arguments == ["-a", "Codex", "/tmp/operator worktree"])
}

private func successfulRun(worktreePath: String, codexThreadURL: URL?) -> OperatorRun {
    OperatorRun(
        id: UUID(),
        taskID: UUID(),
        repositoryID: UUID(),
        status: .triggered,
        worktreePath: worktreePath,
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: "thread-1",
        codexThreadURL: codexThreadURL,
        errorMessage: nil,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        completedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}
