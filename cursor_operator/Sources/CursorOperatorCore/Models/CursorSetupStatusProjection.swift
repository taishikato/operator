public enum CursorRepositorySetupState: Equatable, Sendable {
    case missing
    case registered(count: Int)
}

public struct CursorSetupStatusProjection: Equatable, Sendable {
    public let repositoryState: CursorRepositorySetupState
    public let credentialState: CursorCredentialState

    public static let empty = CursorSetupStatusProjection(
        repositoryState: .missing,
        credentialState: .missing
    )

    public init(repositoryState: CursorRepositorySetupState, credentialState: CursorCredentialState) {
        self.repositoryState = repositoryState
        self.credentialState = credentialState
    }

    public var canSend: Bool {
        switch (repositoryState, credentialState) {
        case (.registered, .ready):
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
}
