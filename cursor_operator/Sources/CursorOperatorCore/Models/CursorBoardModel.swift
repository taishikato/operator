import Combine
import Foundation

@MainActor
public final class CursorBoardModel: ObservableObject {
    @Published public private(set) var projection: CursorBoardProjection
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var pendingRepositoryDraft: CursorRepositoryRegistrationDraft?

    private let store: CursorOperatorStore
    private let repositoryRegistrationService: CursorRepositoryRegistrationService

    public init(
        store: CursorOperatorStore,
        repositoryInspector: any CursorRepositoryInspecting = CursorGitRepositoryInspector()
    ) {
        self.store = store
        repositoryRegistrationService = CursorRepositoryRegistrationService(
            store: store,
            inspector: repositoryInspector
        )
        projection = CursorBoardProjection(tasks: [])
    }

    public func load() throws {
        projection = try CursorBoardProjection.load(from: store)
        errorMessage = nil
    }

    public func createLocalTask(title: String, prompt: String) throws {
        let repository = try firstRepositoryOrCreatePlaceholder()
        _ = try store.createTask(
            repositoryID: repository.id,
            title: title,
            prompt: prompt
        )
        try load()
    }

    public func markDone(taskID: UUID) throws {
        _ = try store.markTaskDone(id: taskID)
        try load()
    }

    public func archive(taskID: UUID) throws {
        _ = try store.archiveTask(id: taskID)
        try load()
    }

    public func prepareRepositoryRegistration(at repositoryURL: URL) throws {
        pendingRepositoryDraft = try repositoryRegistrationService.prepareRepository(at: repositoryURL)
        errorMessage = nil
    }

    public func savePendingRepository(defaultBranch: String) throws {
        guard let pendingRepositoryDraft else {
            return
        }
        _ = try repositoryRegistrationService.saveRepository(
            pendingRepositoryDraft,
            defaultBranch: defaultBranch
        )
        self.pendingRepositoryDraft = nil
        try load()
    }

    public func loadReportingErrors() {
        do {
            try load()
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func createLocalTaskReportingErrors() {
        do {
            try createLocalTask(
                title: "Local Cursor task",
                prompt: "This local placeholder task proves the Cursor Operator SQLite lifecycle."
            )
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func markDoneReportingErrors(taskID: UUID) {
        do {
            try markDone(taskID: taskID)
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func archiveReportingErrors(taskID: UUID) {
        do {
            try archive(taskID: taskID)
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func prepareRepositoryRegistrationReportingErrors(at repositoryURL: URL) {
        do {
            try prepareRepositoryRegistration(at: repositoryURL)
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func savePendingRepositoryReportingErrors(defaultBranch: String) {
        do {
            try savePendingRepository(defaultBranch: defaultBranch)
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private func firstRepositoryOrCreatePlaceholder() throws -> CursorRepository {
        if let repository = try store.repositories().first {
            return repository
        }

        return try store.createRepository(
            name: "Local Cursor Repository",
            localPath: FileManager.default.temporaryDirectory
                .appending(path: "cursor-operator-placeholder", directoryHint: .isDirectory)
                .path,
            githubURL: URL(string: "https://github.com/local/cursor-operator-placeholder")!,
            defaultBranch: "main"
        )
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }
        return "Cursor Operator could not update the board."
    }
}
