import Foundation

public enum ReasoningEffort: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case xhigh
}

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case ready
    case review
    case done
    case archived
}

public struct OperatorTask: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var repositoryID: UUID
    public var title: String
    public var prompt: String
    public var reasoningEffort: ReasoningEffort
    public var status: TaskStatus
    public var createdAt: Date
    public var updatedAt: Date

    public static func new(
        id: UUID = UUID(),
        repositoryID: UUID,
        title: String,
        prompt: String,
        reasoningEffort: ReasoningEffort = .medium,
        now: Date = Date()
    ) -> OperatorTask {
        OperatorTask(
            id: id,
            repositoryID: repositoryID,
            title: title,
            prompt: prompt,
            reasoningEffort: reasoningEffort,
            status: .ready,
            createdAt: now,
            updatedAt: now
        )
    }
}

public enum TaskLifecycleError: Error, Equatable, Sendable {
    case transitionNotAllowed
    case taskIsImmutable
    case taskAlreadyHasSuccessfulRun
}

public enum TaskLifecyclePolicy {
    public static func recordSuccessfulRun(for task: OperatorTask, now: Date = Date()) throws -> OperatorTask {
        guard task.status == .ready else {
            throw TaskLifecycleError.transitionNotAllowed
        }

        return task.with(status: .review, now: now)
    }

    public static func recordFailedRun(for task: OperatorTask) throws -> OperatorTask {
        guard task.status == .ready else {
            throw TaskLifecycleError.transitionNotAllowed
        }

        return task
    }

    /// A started run was aborted before its turn finished (e.g. the CLI hit
    /// --timeout and exited, killing the spawned app-server). The send did
    /// not happen, so the task becomes sendable again.
    public static func recordAbortedRun(for task: OperatorTask, now: Date = Date()) throws -> OperatorTask {
        guard task.status == .review else {
            throw TaskLifecycleError.transitionNotAllowed
        }

        return task.with(status: .ready, now: now)
    }

    public static func moveToDone(_ task: OperatorTask, now: Date = Date()) throws -> OperatorTask {
        guard task.status == .review else {
            throw TaskLifecycleError.transitionNotAllowed
        }

        return task.with(status: .done, now: now)
    }

    public static func archive(_ task: OperatorTask, now: Date = Date()) throws -> OperatorTask {
        guard [.ready, .review, .done].contains(task.status) else {
            throw TaskLifecycleError.transitionNotAllowed
        }

        return task.with(status: .archived, now: now)
    }

    public static func moveToReady(_ task: OperatorTask) throws -> OperatorTask {
        guard task.status == .ready else {
            throw TaskLifecycleError.transitionNotAllowed
        }

        return task
    }

    public static func ensureEditable(_ task: OperatorTask) throws {
        guard task.status == .ready else {
            throw TaskLifecycleError.taskIsImmutable
        }
    }
}

private extension OperatorTask {
    func with(status: TaskStatus, now: Date) -> OperatorTask {
        var copy = self
        copy.status = status
        copy.updatedAt = now
        return copy
    }
}
