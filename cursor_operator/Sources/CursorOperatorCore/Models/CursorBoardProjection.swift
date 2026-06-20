import Foundation

public struct CursorBoardProjection: Equatable, Sendable {
    public let columns: [CursorBoardColumnProjection]
    public let archivedCards: [CursorTaskCardProjection]

    public static func load(from store: CursorOperatorStore) throws -> CursorBoardProjection {
        let tasks = try store.tasks()
        var runReferencesByTaskID: [UUID: CursorTaskRunReference] = [:]
        var failedSendMessagesByTaskID: [UUID: String] = [:]
        for task in tasks {
            let attempts = try store.runAttempts(taskID: task.id)
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
            failedSendMessagesByTaskID: failedSendMessagesByTaskID
        )
    }

    public init(
        tasks: [CursorTask],
        runReferencesByTaskID: [UUID: CursorTaskRunReference] = [:],
        failedSendMessagesByTaskID: [UUID: String] = [:]
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
                            failedSendMessage: failedSendMessagesByTaskID[$0.id]
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
                    failedSendMessage: failedSendMessagesByTaskID[$0.id]
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

    public init(
        task: CursorTask,
        runReference: CursorTaskRunReference? = nil,
        failedSendMessage: String? = nil
    ) {
        id = task.id
        title = task.title
        status = task.status
        hasCursorReference = runReference != nil
        cursorRunID = runReference?.cursorRunID
        cursorURL = runReference?.cursorURL
        self.failedSendMessage = failedSendMessage
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
