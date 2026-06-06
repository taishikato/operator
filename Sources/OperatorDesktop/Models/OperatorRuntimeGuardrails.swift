public enum OperatorRuntimeResponsibility: Equatable, Sendable {
    case scheduling
    case triggerQueue
    case concurrencyControl
    case backlogColumn
    case runningColumn
    case reviewToReadyMovement
    case rerunAfterSuccessfulSend
    case hardDelete
    case automaticWorktreeCleanup
    case pullRequestCreation
    case branchCreation
    case diffInspection
    case changedFileCount
    case testResultTracking
    case commitStatusTracking
    case codexCompletionTracking
    case appServerRawEventPersistence
    case codexTranscriptPersistence
}

public struct OperatorRuntimeGuardrails: Equatable, Sendable {
    public let forbiddenResponsibilities: [OperatorRuntimeResponsibility]
    public let allowedBoardColumns: [BoardColumnID]
    public let allowedNavigationDestinations: [OperatorDestination]
    public let allowedRunPersistenceColumns: [String]
    public let forbiddenRunPersistenceColumns: Set<String>
    public let forbiddenFailureErrorMessageSubstrings: [String]
    public let forbiddenVisibleLabels: Set<String>
    public let maximumFailureErrorMessageLength: Int

    public static let mvp = OperatorRuntimeGuardrails(
        forbiddenResponsibilities: [
            .scheduling,
            .triggerQueue,
            .concurrencyControl,
            .backlogColumn,
            .runningColumn,
            .reviewToReadyMovement,
            .rerunAfterSuccessfulSend,
            .hardDelete,
            .automaticWorktreeCleanup,
            .pullRequestCreation,
            .branchCreation,
            .diffInspection,
            .changedFileCount,
            .testResultTracking,
            .commitStatusTracking,
            .codexCompletionTracking,
            .appServerRawEventPersistence,
            .codexTranscriptPersistence
        ],
        allowedBoardColumns: [.ready, .review, .done],
        allowedNavigationDestinations: [.board, .archived, .settings],
        allowedRunPersistenceColumns: [
            "id",
            "taskID",
            "repositoryID",
            "status",
            "worktreePath",
            "baseBranch",
            "baseRef",
            "codexThreadID",
            "codexThreadURL",
            "errorMessage",
            "createdAt",
            "completedAt"
        ],
        forbiddenRunPersistenceColumns: [
            "rawEvent",
            "rawEvents",
            "appServerEvent",
            "appServerEvents",
            "transcript",
            "codexTranscript",
            "completionStatus",
            "diff",
            "changedFileCount",
            "testResult",
            "commitStatus",
            "pullRequestURL"
        ],
        forbiddenFailureErrorMessageSubstrings: [
            "rawEvent",
            "rawEvents",
            "appServerEvent",
            "appServerEvents",
            "transcript",
            "codexTranscript"
        ],
        forbiddenVisibleLabels: [
            "Backlog",
            "Running",
            "Schedule",
            "Cron",
            "Timezone",
            "Queue",
            "Concurrency",
            "Rerun",
            "Delete",
            "Create PR",
            "Pull Request",
            "Branch",
            "Diff",
            "Changed Files",
            "Test Result",
            "Commit Status",
            "Codex Completion"
        ],
        maximumFailureErrorMessageLength: 160
    )
}
