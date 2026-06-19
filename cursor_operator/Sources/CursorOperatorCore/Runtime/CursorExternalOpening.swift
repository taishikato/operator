import AppKit
import Foundation

public enum CursorExternalOpenAction: Equatable, Sendable {
    case openURL(URL)
    case copyRunID(String)
    case openDashboard(URL)
}

@MainActor
public protocol CursorExternalOpening {
    func perform(_ action: CursorExternalOpenAction)
}

public enum CursorOpenInCursorError: Error, Equatable, LocalizedError, Sendable {
    case noCursorReference

    public var errorDescription: String? {
        switch self {
        case .noCursorReference:
            "This task does not have a Cursor run reference."
        }
    }
}

@MainActor
public struct SystemCursorExternalOpener: CursorExternalOpening {
    public init() {}

    public func perform(_ action: CursorExternalOpenAction) {
        switch action {
        case let .openURL(url), let .openDashboard(url):
            NSWorkspace.shared.open(url)
        case let .copyRunID(runID):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(runID, forType: .string)
        }
    }
}

public enum CursorCloudAgentDestinations {
    public static let dashboard = URL(string: "https://cursor.com/agents")!
}
