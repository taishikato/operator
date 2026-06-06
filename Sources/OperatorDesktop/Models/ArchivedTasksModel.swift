import Foundation

public struct ArchivedTasksProjection: Equatable, Sendable {
    public let tasks: [ArchivedTaskProjection]

    public static func load(from store: OperatorStore) throws -> ArchivedTasksProjection {
        let repositories = try store.repositories()
        let tasks = try store.tasks()
        let latestRunsByTaskID = try store.latestRunsByTaskID()
        return ArchivedTasksProjection(
            repositories: repositories,
            tasks: tasks,
            latestRunsByTaskID: latestRunsByTaskID
        )
    }

    public init(
        repositories: [OperatorRepository],
        tasks: [OperatorTask],
        latestRunsByTaskID: [UUID: OperatorRun] = [:]
    ) {
        let repositoriesByID = Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) })
        self.tasks = tasks
            .filter { $0.status == .archived }
            .map { task in
                ArchivedTaskProjection(
                    task: task,
                    repositoryName: repositoriesByID[task.repositoryID]?.name ?? "Unknown Repository",
                    latestRun: latestRunsByTaskID[task.id]
                )
            }
    }
}

public struct ArchivedTaskProjection: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let repositoryBadge: String
    public let reasoningBadge: String
    public let codexOpenTarget: CodexOpenTarget?
    public let codexOpenLabel: String

    public var canOpenInCodexApp: Bool {
        codexOpenTarget != nil
    }

    public init(task: OperatorTask, repositoryName: String, latestRun: OperatorRun? = nil) {
        id = task.id
        title = task.title
        repositoryBadge = repositoryName
        reasoningBadge = task.reasoningEffort.displayLabel
        codexOpenTarget = latestRun.flatMap(CodexOpenTarget.init(run:))
        codexOpenLabel = "Open in Codex App"
    }
}

@MainActor
public final class ArchivedTasksModel: ObservableObject {
    @Published public private(set) var projection: ArchivedTasksProjection
    @Published public private(set) var errorMessage: String?

    private let store: OperatorStore
    private let codexOpener: (any CodexAppOpening)?

    public init(store: OperatorStore, codexOpener: (any CodexAppOpening)? = NSWorkspaceCodexAppOpener()) {
        self.store = store
        self.codexOpener = codexOpener
        projection = ArchivedTasksProjection(repositories: [], tasks: [])
    }

    public func load() throws {
        projection = try ArchivedTasksProjection.load(from: store)
        errorMessage = nil
    }

    public func loadReportingErrors() {
        do {
            try load()
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func openTaskInCodexAppReportingErrors(taskID: UUID) {
        guard
            let target = projection.tasks.first(where: { $0.id == taskID })?.codexOpenTarget,
            let codexOpener
        else {
            errorMessage = CodexAppOpenError.openFailed.errorDescription
            return
        }

        do {
            try codexOpener.open(target)
            errorMessage = nil
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    nonisolated private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }
        return "Unable to open Codex App."
    }
}
