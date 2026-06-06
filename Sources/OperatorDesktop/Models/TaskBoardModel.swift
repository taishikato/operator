import Foundation

public enum TaskCreationError: Error, Equatable, Sendable {
    case repositoryRequired
    case titleRequired
    case promptRequired
}

public struct TaskCreationDraft: Equatable, Sendable {
    public var repositoryID: UUID?
    public var title: String
    public var prompt: String
    public var reasoningEffort: ReasoningEffort

    public init(
        repositoryID: UUID? = nil,
        title: String = "",
        prompt: String = "",
        reasoningEffort: ReasoningEffort = .medium
    ) {
        self.repositoryID = repositoryID
        self.title = title
        self.prompt = prompt
        self.reasoningEffort = reasoningEffort
    }

    public func createTask(in store: OperatorStore) throws -> OperatorTask {
        guard let repositoryID else {
            throw TaskCreationError.repositoryRequired
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw TaskCreationError.titleRequired
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw TaskCreationError.promptRequired
        }

        return try store.createTask(
            repositoryID: repositoryID,
            title: trimmedTitle,
            prompt: trimmedPrompt,
            reasoningEffort: reasoningEffort
        )
    }
}

public struct ReasoningEffortOption: Equatable, Identifiable, Sendable {
    public var id: String { effort.rawValue }

    public let effort: ReasoningEffort
    public let label: String

    public static let all: [ReasoningEffortOption] = ReasoningEffort.allCases.map {
        ReasoningEffortOption(effort: $0, label: $0.displayLabel)
    }
}

public extension ReasoningEffort {
    var displayLabel: String {
        switch self {
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        case .xhigh:
            "Extra High"
        }
    }
}

public struct RepositoryFilterOption: Equatable, Identifiable, Sendable {
    public let id: UUID?
    public let name: String

    public static let allRepositories = RepositoryFilterOption(id: nil, name: "All Repositories")
}

public struct TaskBoardProjection: Equatable, Sendable {
    public let repositoryFilters: [RepositoryFilterOption]
    public let columns: [TaskBoardColumnProjection]
    private let inspectorsByTaskID: [UUID: TaskInspectorProjection]

    public static func load(
        from store: OperatorStore,
        selectedRepositoryID: UUID? = nil
    ) throws -> TaskBoardProjection {
        let repositories = try store.repositories()
        let tasks = try store.tasks()
        let latestRunsByTaskID = try store.latestRunsByTaskID()

        return TaskBoardProjection(
            repositories: repositories,
            tasks: tasks,
            latestRunsByTaskID: latestRunsByTaskID,
            selectedRepositoryID: selectedRepositoryID
        )
    }

    public init(
        repositories: [OperatorRepository],
        tasks: [OperatorTask],
        runsByTaskID: [UUID: [OperatorRun]] = [:],
        latestRunsByTaskID: [UUID: OperatorRun]? = nil,
        selectedRepositoryID: UUID? = nil
    ) {
        let repositoriesByID = Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) })
        let latestRunsByTaskID = latestRunsByTaskID ?? runsByTaskID.compactMapValues(\.last)
        let filteredTasks = tasks.filter { task in
            guard task.status != .archived else {
                return false
            }
            guard let selectedRepositoryID else {
                return true
            }
            return task.repositoryID == selectedRepositoryID
        }

        repositoryFilters = [.allRepositories] + repositories.map {
            RepositoryFilterOption(id: $0.id, name: $0.name)
        }
        columns = [.ready, .review, .done].map { status in
            TaskBoardColumnProjection(
                id: BoardColumnID(status: status),
                title: status.columnTitle,
                cards: filteredTasks
                    .filter { $0.status == status }
                    .map { task in
                        TaskCardProjection(
                            task: task,
                            repositoryName: repositoriesByID[task.repositoryID]?.name ?? "Unknown Repository",
                            latestRun: latestRunsByTaskID[task.id]
                        )
                    }
            )
        }
        inspectorsByTaskID = Dictionary(
            uniqueKeysWithValues: filteredTasks.compactMap { task in
                guard let repository = repositoriesByID[task.repositoryID] else {
                    return nil
                }
                return (task.id, TaskInspectorProjection(task: task, repository: repository))
            }
        )
    }

    public func column(_ id: BoardColumnID) -> TaskBoardColumnProjection {
        columns.first { $0.id == id } ?? TaskBoardColumnProjection(id: id, title: "", cards: [])
    }

    public func inspector(taskID: UUID) -> TaskInspectorProjection? {
        inspectorsByTaskID[taskID]
    }
}

public struct TaskBoardColumnProjection: Equatable, Identifiable, Sendable {
    public let id: BoardColumnID
    public let title: String
    public let cards: [TaskCardProjection]
}

public struct TaskCardProjection: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let repositoryBadge: String
    public let reasoningBadge: String
    public let triggerStateBadge: String?
    public let promptPreview: String?

    public init(task: OperatorTask, repositoryName: String, latestRun: OperatorRun? = nil) {
        id = task.id
        title = task.title
        repositoryBadge = repositoryName
        reasoningBadge = task.reasoningEffort.displayLabel
        triggerStateBadge = latestRun?.triggerStateBadge
        promptPreview = nil
    }
}

public struct TaskInspectorProjection: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let repositoryName: String
    public let title: String
    public let prompt: String
    public let reasoningEffort: ReasoningEffort
    public let isEditable: Bool

    public init(task: OperatorTask, repository: OperatorRepository) {
        id = task.id
        repositoryName = repository.name
        title = task.title
        prompt = task.prompt
        reasoningEffort = task.reasoningEffort
        isEditable = task.status == .ready
    }
}

public struct TaskInspectorDraft: Equatable, Sendable {
    public var title: String
    public var prompt: String
    public var reasoningEffort: ReasoningEffort

    public init(task: OperatorTask) {
        title = task.title
        prompt = task.prompt
        reasoningEffort = task.reasoningEffort
    }

    public init(inspector: TaskInspectorProjection) {
        title = inspector.title
        prompt = inspector.prompt
        reasoningEffort = inspector.reasoningEffort
    }

    public func save(taskID: UUID, in store: OperatorStore) throws -> OperatorTask {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw TaskCreationError.titleRequired
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw TaskCreationError.promptRequired
        }

        return try store.updateTaskContent(
            id: taskID,
            title: trimmedTitle,
            prompt: trimmedPrompt,
            reasoningEffort: reasoningEffort
        )
    }
}

@MainActor
public final class TaskBoardModel: ObservableObject {
    @Published public private(set) var projection: TaskBoardProjection
    @Published public var creationDraft: TaskCreationDraft
    @Published public private(set) var selectedRepositoryID: UUID?
    @Published public private(set) var selectedTaskID: UUID?
    @Published public var inspectorDraft: TaskInspectorDraft?
    @Published public private(set) var errorMessage: String?

    private let store: OperatorStore

    public init(store: OperatorStore) {
        self.store = store
        projection = TaskBoardProjection(repositories: [], tasks: [])
        creationDraft = TaskCreationDraft()
    }

    public func load() throws {
        projection = try TaskBoardProjection.load(from: store, selectedRepositoryID: selectedRepositoryID)
        syncInspectorDraft()
        errorMessage = nil
    }

    public func loadReportingErrors() {
        do {
            try load()
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func selectRepository(_ repositoryID: UUID?) {
        selectedRepositoryID = repositoryID
        loadReportingErrors()
    }

    public func createTask() throws {
        let task = try creationDraft.createTask(in: store)
        creationDraft = TaskCreationDraft(repositoryID: selectedRepositoryID ?? task.repositoryID)
        selectedTaskID = task.id
        try load()
    }

    public func createTaskReportingErrors() {
        do {
            try createTask()
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func selectTask(_ taskID: UUID?) {
        if selectedTaskID != taskID {
            inspectorDraft = nil
        }
        selectedTaskID = taskID
        syncInspectorDraft()
    }

    public func saveSelectedInspectorTask() throws {
        guard let selectedTaskID, let inspectorDraft else {
            return
        }

        _ = try inspectorDraft.save(taskID: selectedTaskID, in: store)
        self.inspectorDraft = nil
        try load()
    }

    public func saveSelectedInspectorTaskReportingErrors() {
        do {
            try saveSelectedInspectorTask()
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private func syncInspectorDraft() {
        guard
            let selectedTaskID,
            let inspector = projection.inspector(taskID: selectedTaskID)
        else {
            selectedTaskID = nil
            inspectorDraft = nil
            return
        }

        if inspectorDraft == nil {
            inspectorDraft = TaskInspectorDraft(inspector: inspector)
        }
    }

    nonisolated private static func userFacingMessage(for error: Error) -> String {
        switch error {
        case TaskCreationError.repositoryRequired:
            return "Choose a repository."
        case TaskCreationError.titleRequired:
            return "Enter a task title."
        case TaskCreationError.promptRequired:
            return "Enter a prompt."
        default:
            if let localizedError = error as? LocalizedError,
               let errorDescription = localizedError.errorDescription {
                return errorDescription
            }
            return "Unable to update the board."
        }
    }
}

private extension BoardColumnID {
    init(status: TaskStatus) {
        switch status {
        case .ready:
            self = .ready
        case .review:
            self = .review
        case .done:
            self = .done
        case .archived:
            self = .archived
        }
    }
}

private extension TaskStatus {
    var columnTitle: String {
        switch self {
        case .ready:
            "Ready"
        case .review:
            "Review"
        case .done:
            "Done"
        case .archived:
            "Archived"
        }
    }
}

private extension OperatorRun {
    var triggerStateBadge: String {
        switch status {
        case .triggerFailed:
            "Failed to send"
        case .triggered:
            "Sent to Codex"
        }
    }
}
