public enum CursorOperatorOutOfScopeCapability: Equatable, Hashable, Sendable {
    case localCursorRuntime
    case promptAugmentation
    case branchOwnership
    case pullRequestOrchestration
    case rawLogs
    case diffs
    case commits
    case testResults
    case resultClassification
    case cursorDesktopDeepLinks
    case webhooks
    case cursorRunPolling
}

public enum CursorContinuationSurface: Equatable, Sendable {
    case webURL
    case copyRunID
    case dashboard
}

public enum CursorOperatorMVPScope {
    public static let outOfScope: Set<CursorOperatorOutOfScopeCapability> = [
        .localCursorRuntime,
        .promptAugmentation,
        .branchOwnership,
        .pullRequestOrchestration,
        .rawLogs,
        .diffs,
        .commits,
        .testResults,
        .resultClassification,
        .cursorDesktopDeepLinks,
        .webhooks,
        .cursorRunPolling
    ]

    public static let disallowedAutomaticGitCommands = ["fetch", "pull", "push", "merge", "rebase"]
    public static let cursorContinuations: [CursorContinuationSurface] = [.webURL, .copyRunID, .dashboard]
}
