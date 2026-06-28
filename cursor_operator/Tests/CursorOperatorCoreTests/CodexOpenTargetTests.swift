import Foundation
import Testing
@testable import CursorOperatorCore

@Test func codexOpenTargetPrefersThreadURLAndFallsBackToWorktreePath() throws {
    let threadRun = codexRun(
        codexThreadID: "thread-123",
        codexThreadURL: nil,
        worktreePath: "/tmp/operator-worktree"
    )
    let fallbackRun = codexRun(
        codexThreadID: nil,
        codexThreadURL: nil,
        worktreePath: "/tmp/operator-worktree"
    )

    #expect(CodexOpenTarget(run: threadRun) == .url(URL(string: "codex://threads/thread-123")!))
    #expect(CodexOpenTarget(run: fallbackRun) == .worktree(URL(filePath: "/tmp/operator-worktree", directoryHint: .isDirectory)))
    #expect(CodexOpenCommand(target: .url(URL(string: "codex://threads/thread-123")!)).arguments == [
        "codex://threads/thread-123"
    ])
    #expect(CodexOpenCommand(target: .worktree(URL(filePath: "/tmp/operator-worktree", directoryHint: .isDirectory))).arguments == [
        "-a", "Codex", "/tmp/operator-worktree"
    ])
}

private func codexRun(codexThreadID: String?, codexThreadURL: URL?, worktreePath: String?) -> OperatorRun {
    OperatorRun(
        id: UUID(),
        taskID: UUID(),
        repositoryID: UUID(),
        status: .succeeded,
        repositoryURL: URL(filePath: worktreePath ?? "/tmp/repository"),
        startingRef: "abc123",
        model: CodexModel.fixed,
        autoCreatePR: false,
        prompt: "Prompt",
        harness: .codex,
        reasoningEffort: .medium,
        useFastModel: false,
        cursorAgentID: nil,
        cursorRunID: nil,
        cursorURL: nil,
        worktreePath: worktreePath,
        baseBranch: "main",
        baseRef: "abc123",
        codexThreadID: codexThreadID,
        codexThreadURL: codexThreadURL,
        errorMessage: nil,
        createdAt: Date(timeIntervalSince1970: 0),
        completedAt: Date(timeIntervalSince1970: 0)
    )
}
