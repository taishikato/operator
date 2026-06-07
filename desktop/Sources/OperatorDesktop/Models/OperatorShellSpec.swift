public struct OperatorShellSpec: Equatable, Sendable {
    public let launchDestination: OperatorDestination
    public let board: BoardSpec
    public let navigationDestinations: [OperatorDestination]

    public static let mvp = OperatorShellSpec(
        launchDestination: .board,
        board: BoardSpec(
            columns: [
                BoardColumnSpec(id: .ready, title: "Ready"),
                BoardColumnSpec(id: .review, title: "Running"),
                BoardColumnSpec(id: .done, title: "Done")
            ],
            emptyState: BoardEmptyState(
                title: "No repositories or tasks yet",
                message: "Ready, Running, and Done are empty right now."
            ),
            reservesInspectorPanel: true
        ),
        navigationDestinations: [.board, .archived, .settings]
    )
}

public enum OperatorDestination: Equatable, Sendable {
    case board
    case archived
    case settings
}

public enum OperatorSidebarSelection: CaseIterable, Equatable, Sendable {
    case board
    case archived

    public init?(destination: OperatorDestination) {
        switch destination {
        case .board:
            self = .board
        case .archived:
            self = .archived
        case .settings:
            return nil
        }
    }
}

public struct BoardSpec: Equatable, Sendable {
    public let columns: [BoardColumnSpec]
    public let emptyState: BoardEmptyState
    public let reservesInspectorPanel: Bool
}

public struct BoardColumnSpec: Equatable, Identifiable, Sendable {
    public let id: BoardColumnID
    public let title: String
}

public enum BoardColumnID: Equatable, Sendable {
    case ready
    case review
    case done
    case archived
}

public struct BoardEmptyState: Equatable, Sendable {
    public let title: String
    public let message: String
}
