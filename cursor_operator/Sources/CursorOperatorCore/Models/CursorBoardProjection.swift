import Foundation

public struct CursorBoardProjection: Equatable, Sendable {
    public let columns: [CursorBoardColumnProjection]
    public let archivedCards: [CursorTaskCardProjection]

    public static func load(from store: CursorOperatorStore) throws -> CursorBoardProjection {
        let tasks = try store.tasks()
        var runReferencesByTaskID: [UUID: CursorTaskRunReference] = [:]
        var failedSendMessagesByTaskID: [UUID: String] = [:]
        var runHistoryByTaskID: [UUID: [CursorTaskRunProjection]] = [:]
        for task in tasks {
            let attempts = try store.runAttempts(taskID: task.id)
            runHistoryByTaskID[task.id] = attempts.map(CursorTaskRunProjection.init)
            let successfulAttempt = attempts
                .last { $0.status == .succeeded }
            if let successfulAttempt {
                runReferencesByTaskID[task.id] = CursorTaskRunReference(
                    cursorAgentID: successfulAttempt.cursorAgentID,
                    cursorRunID: successfulAttempt.cursorRunID,
                    cursorURL: successfulAttempt.cursorURL
                )
            }
            if let failedAttempt = attempts.last(where: { $0.errorMessage != nil }),
               let errorMessage = failedAttempt.errorMessage {
                failedSendMessagesByTaskID[task.id] = errorMessage
            }
        }
        return CursorBoardProjection(
            tasks: tasks,
            runReferencesByTaskID: runReferencesByTaskID,
            failedSendMessagesByTaskID: failedSendMessagesByTaskID,
            runHistoryByTaskID: runHistoryByTaskID
        )
    }

    public init(
        tasks: [CursorTask],
        runReferencesByTaskID: [UUID: CursorTaskRunReference] = [:],
        failedSendMessagesByTaskID: [UUID: String] = [:],
        runHistoryByTaskID: [UUID: [CursorTaskRunProjection]] = [:]
    ) {
        let activeTasks = tasks.filter { $0.status != .archived }
        columns = [CursorTaskStatus.ready, .running, .failed, .done].map { status in
            CursorBoardColumnProjection(
                id: CursorBoardColumnID(status: status),
                title: status.columnTitle,
                cards: activeTasks
                    .filter { $0.status == status }
                    .map {
                        CursorTaskCardProjection(
                            task: $0,
                            runReference: runReferencesByTaskID[$0.id],
                            failedSendMessage: failedSendMessagesByTaskID[$0.id],
                            runHistory: runHistoryByTaskID[$0.id] ?? []
                        )
                    }
            )
        }
        archivedCards = tasks
            .filter { $0.status == .archived }
            .map {
                CursorTaskCardProjection(
                    task: $0,
                    runReference: runReferencesByTaskID[$0.id],
                    failedSendMessage: failedSendMessagesByTaskID[$0.id],
                    runHistory: runHistoryByTaskID[$0.id] ?? []
                )
            }
    }
}

public struct CursorBoardColumnProjection: Equatable, Identifiable, Sendable {
    public let id: CursorBoardColumnID
    public let title: String
    public let cards: [CursorTaskCardProjection]
}

public struct CursorTaskCardProjection: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let status: CursorTaskStatus
    public let hasCursorReference: Bool
    public let cursorRunID: String?
    public let cursorURL: URL?
    public let failedSendMessage: String?
    public let latestRun: CursorTaskRunProjection?
    public let runHistory: [CursorTaskRunProjection]

    public init(
        task: CursorTask,
        runReference: CursorTaskRunReference? = nil,
        failedSendMessage: String? = nil,
        runHistory: [CursorTaskRunProjection] = []
    ) {
        id = task.id
        title = task.title
        status = task.status
        hasCursorReference = runReference != nil
        cursorRunID = runReference?.cursorRunID
        cursorURL = runReference?.cursorURL
        self.failedSendMessage = failedSendMessage
        latestRun = runHistory.last
        self.runHistory = runHistory
    }

    public var canOpenInCursor: Bool {
        hasCursorReference
    }

    public var runStatusText: String? {
        switch status {
        case .ready:
            nil
        case .running:
            "Run in progress"
        case .failed:
            "Run failed"
        case .done:
            "Run complete"
        case .archived:
            nil
        }
    }
}

public struct CursorTaskRunProjection: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let status: CursorRunAttemptStatus
    public let harness: CursorHarness
    public let prompt: String
    public let errorMessage: String?
    public let cursorRunID: String?
    public let cursorURL: URL?
    public let createdAt: Date
    public let completedAt: Date

    public init(run: CursorRunAttempt) {
        id = run.id
        status = run.status
        harness = run.harness
        prompt = run.prompt
        errorMessage = run.errorMessage
        cursorRunID = run.cursorRunID
        cursorURL = run.cursorURL
        createdAt = run.createdAt
        completedAt = run.completedAt
    }
}

public struct CursorTaskRunReference: Equatable, Sendable {
    public let cursorAgentID: String?
    public let cursorRunID: String?
    public let cursorURL: URL?

    public init(cursorAgentID: String?, cursorRunID: String?, cursorURL: URL?) {
        self.cursorAgentID = cursorAgentID
        self.cursorRunID = cursorRunID
        self.cursorURL = cursorURL
    }
}

private extension CursorBoardColumnID {
    init(status: CursorTaskStatus) {
        switch status {
        case .ready:
            self = .ready
        case .running:
            self = .running
        case .failed:
            self = .failed
        case .done:
            self = .done
        case .archived:
            self = .archived
        }
    }
}

private extension CursorTaskStatus {
    var columnTitle: String {
        switch self {
        case .ready:
            "Ready"
        case .running:
            "Running"
        case .failed:
            "Failed"
        case .done:
            "Done"
        case .archived:
            "Archived"
        }
    }
}
