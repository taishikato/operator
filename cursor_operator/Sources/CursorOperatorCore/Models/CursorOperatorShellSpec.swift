import Foundation

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
                CursorBoardColumnSpec(id: .failed, title: "Failed"),
                CursorBoardColumnSpec(id: .done, title: "Done")
            ],
            commands: [
                CursorBoardCommandSpec(id: .newTask, title: "New Cursor Task", keyboardShortcut: "Command-N"),
                CursorBoardCommandSpec(id: .addRepository, title: "Add Repository", keyboardShortcut: "Command-O")
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

    public func selectionAfterAppMenuCommand(_ command: CursorBoardCommandID) -> CursorOperatorSidebarSelection {
        switch command {
        case .newTask, .addRepository:
            .board
        }
    }
}

public struct CursorBoardSpec: Equatable, Sendable {
    public let columns: [CursorBoardColumnSpec]
    public let commands: [CursorBoardCommandSpec]
    public let emptyState: CursorBoardEmptyState
}

public struct CursorBoardColumnSpec: Equatable, Identifiable, Sendable {
    public let id: CursorBoardColumnID
    public let title: String
}

public enum CursorBoardCommandID: Equatable, Sendable {
    case newTask
    case addRepository
}

public struct CursorBoardCommandSpec: Equatable, Identifiable, Sendable {
    public let id: CursorBoardCommandID
    public let title: String
    public let keyboardShortcut: String
}

public enum CursorBoardColumnID: Equatable, Sendable {
    case ready
    case running
    case failed
    case done
    case archived
}

public struct CursorBoardEmptyState: Equatable, Sendable {
    public let title: String
    public let message: String
}

public extension Notification.Name {
    static let cursorOperatorNewTaskCommand = Notification.Name("com.focus.cursor-operator.new-task")
    static let cursorOperatorAddRepositoryCommand = Notification.Name("com.focus.cursor-operator.add-repository")
    static let cursorOperatorToggleSidebarCommand = Notification.Name("com.focus.cursor-operator.toggle-sidebar")
    static let cursorOperatorCredentialsChanged = Notification.Name("com.focus.cursor-operator.credentials-changed")
}
