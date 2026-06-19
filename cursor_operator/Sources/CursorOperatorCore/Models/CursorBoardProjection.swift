import Foundation

public struct CursorBoardProjection: Equatable, Sendable {
    public let columns: [CursorBoardColumnProjection]

    public static func load(from store: CursorOperatorStore) throws -> CursorBoardProjection {
        try CursorBoardProjection(tasks: store.tasks())
    }

    public init(tasks: [CursorTask]) {
        let activeTasks = tasks.filter { $0.status != .archived }
        columns = [CursorTaskStatus.ready, .running, .done].map { status in
            CursorBoardColumnProjection(
                id: CursorBoardColumnID(status: status),
                title: status.columnTitle,
                cards: activeTasks
                    .filter { $0.status == status }
                    .map { CursorTaskCardProjection(task: $0) }
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

    public init(task: CursorTask) {
        id = task.id
        title = task.title
    }
}

private extension CursorBoardColumnID {
    init(status: CursorTaskStatus) {
        switch status {
        case .ready:
            self = .ready
        case .running:
            self = .running
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
        case .done:
            "Done"
        case .archived:
            "Archived"
        }
    }
}
