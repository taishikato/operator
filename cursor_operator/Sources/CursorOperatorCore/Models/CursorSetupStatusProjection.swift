public enum CursorRepositorySetupState: Equatable, Sendable {
    case missing
    case registered(count: Int)
}

public enum CursorNodeSetupState: Equatable, Sendable {
    case missing
    case ready(version: String)
}

public enum CodexSetupState: Equatable, Sendable {
    case notChecked
    case ready(binaryPath: String)
    case notFound
    case unavailable(String)
}

public struct CursorSetupStatusProjection: Equatable, Sendable {
    public let repositoryState: CursorRepositorySetupState
    public let credentialState: CursorCredentialState
    public let nodeState: CursorNodeSetupState
    public let codexState: CodexSetupState
    public let selectedHarness: CursorHarness

    public static let empty = CursorSetupStatusProjection(
        repositoryState: .missing,
        credentialState: .missing,
        nodeState: .missing
    )

    public init(
        repositoryState: CursorRepositorySetupState,
        credentialState: CursorCredentialState,
        nodeState: CursorNodeSetupState,
        codexState: CodexSetupState = .notChecked,
        selectedHarness: CursorHarness = .cursor
    ) {
        self.repositoryState = repositoryState
        self.credentialState = credentialState
        self.nodeState = nodeState
        self.codexState = codexState
        self.selectedHarness = selectedHarness
    }

    public var canSend: Bool {
        guard case .registered = repositoryState else {
            return false
        }

        switch selectedHarness {
        case .cursor:
            switch (credentialState, nodeState) {
            case (.ready, .ready):
                return true
            default:
                return false
            }
        case .codex:
            switch codexState {
            case .ready:
                return true
            case .notChecked, .notFound, .unavailable:
                return false
            }
        case .claudeCode:
            return false
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
        guard case .registered = repositoryState else {
            return "Register a repository before sending."
        }

        switch selectedHarness {
        case .cursor:
            switch (credentialState, nodeState) {
            case (.missing, _):
                return "Cursor API key is required before sending."
            case (_, .missing):
                return "Node.js 22.13 or newer is required for the Cursor SDK."
            case (.ready, .ready):
                return ""
            }
        case .codex:
            switch codexState {
            case .ready:
                return ""
            case .notChecked, .notFound, .unavailable:
                return "Codex must be ready before sending."
            }
        case .claudeCode:
            return "Claude Code sending is not available yet."
        }
    }

    public var codexMessage: String {
        switch codexState {
        case .notChecked:
            "Codex: not checked"
        case let .ready(binaryPath):
            "Codex: \(binaryPath)"
        case .notFound:
            "Codex: not found"
        case let .unavailable(message):
            "Codex: \(message)"
        }
    }

    public var codexIconName: String {
        switch codexState {
        case .ready:
            "checkmark.circle"
        case .notChecked:
            "questionmark.circle"
        case .notFound, .unavailable:
            "exclamationmark.triangle"
        }
    }

    public var selectedHarnessMessage: String {
        switch selectedHarness {
        case .cursor:
            "Harness: Cursor"
        case .codex:
            "Harness: Codex"
        case .claudeCode:
            "Harness: Claude Code"
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
