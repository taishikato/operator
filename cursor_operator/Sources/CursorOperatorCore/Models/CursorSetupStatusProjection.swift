public enum CursorRepositorySetupState: Equatable, Sendable {
    case missing
    case registered(count: Int)
}

public enum CursorNodeSetupState: Equatable, Sendable {
    case missing
    case ready(version: String)
}

public struct CursorSetupStatusProjection: Equatable, Sendable {
    public let repositoryState: CursorRepositorySetupState
    public let credentialState: CursorCredentialState
    public let nodeState: CursorNodeSetupState

    public static let empty = CursorSetupStatusProjection(
        repositoryState: .missing,
        credentialState: .missing,
        nodeState: .missing
    )

    public init(
        repositoryState: CursorRepositorySetupState,
        credentialState: CursorCredentialState,
        nodeState: CursorNodeSetupState
    ) {
        self.repositoryState = repositoryState
        self.credentialState = credentialState
        self.nodeState = nodeState
    }

    public var canSend: Bool {
        switch (repositoryState, credentialState, nodeState) {
        case (.registered, .ready, .ready):
            true
        default:
            false
        }
    }

    public var repositoryMessage: String {
        switch repositoryState {
        case .missing:
            "Repository: none registered"
        case let .registered(count):
            "Repository: \(count) registered"
        }
    }

    public var credentialMessage: String {
        switch credentialState {
        case .missing:
            "Cursor API key: missing"
        case .ready:
            "Cursor API key: ready"
        }
    }

    public var nodeMessage: String {
        switch nodeState {
        case .missing:
            "Node.js: 22.13+ required"
        case let .ready(version):
            "Node.js: \(version)"
        }
    }

    public var sendDisabledReason: String {
        switch (repositoryState, credentialState, nodeState) {
        case (.missing, _, _):
            "Register a repository before sending."
        case (_, .missing, _):
            "Cursor API key is required before sending."
        case (_, _, .missing):
            "Node.js 22.13 or newer is required for the Cursor SDK."
        case (.registered, .ready, .ready):
            ""
        }
    }

    public var repositoryIconName: String {
        switch repositoryState {
        case .missing:
            "folder.badge.questionmark"
        case .registered:
            "folder"
        }
    }

    public var credentialIconName: String {
        switch credentialState {
        case .missing:
            "key.slash"
        case .ready:
            "key"
        }
    }

    public var nodeIconName: String {
        switch nodeState {
        case .missing:
            "exclamationmark.triangle"
        case .ready:
            "checkmark.circle"
        }
    }
}
