public struct CursorOperatorShellSpec: Equatable, Sendable {
    public let launchDestination: CursorOperatorDestination
    public let board: CursorBoardSpec
    public let navigationDestinations: [CursorOperatorDestination]
    public let sceneDestinations: [CursorOperatorDestination]

    public static let mvp = CursorOperatorShellSpec(
        launchDestination: .board,
        board: CursorBoardSpec(
            columns: [
                CursorBoardColumnSpec(id: .ready, title: "Ready"),
                CursorBoardColumnSpec(id: .running, title: "Running"),
                CursorBoardColumnSpec(id: .done, title: "Done")
            ],
            emptyState: CursorBoardEmptyState(
                title: "No Cursor tasks yet",
                message: "Ready, Running, and Done are empty right now."
            )
        ),
        navigationDestinations: [.board, .archived],
        sceneDestinations: [.settings]
    )
}

public enum CursorOperatorDestination: Equatable, Hashable, Sendable {
    case board
    case archived
    case settings
}

public enum CursorOperatorSidebarSelection: CaseIterable, Equatable, Hashable, Sendable {
    case board
    case archived

    public init?(destination: CursorOperatorDestination) {
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

public struct CursorBoardSpec: Equatable, Sendable {
    public let columns: [CursorBoardColumnSpec]
    public let emptyState: CursorBoardEmptyState
}

public struct CursorBoardColumnSpec: Equatable, Identifiable, Sendable {
    public let id: CursorBoardColumnID
    public let title: String
}

public enum CursorBoardColumnID: Equatable, Sendable {
    case ready
    case running
    case done
    case archived
}

public struct CursorBoardEmptyState: Equatable, Sendable {
    public let title: String
    public let message: String
}
