import Foundation

public enum CursorModel {
    public static let fixed = "composer-2.5"
}

public enum CursorHarness: String, Codable, CaseIterable, Sendable {
    case cursor
    case codex
    case claudeCode = "claude-code"
}

public enum CursorReasoningEffort: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}

public enum CursorTaskStatus: String, Codable, CaseIterable, Sendable {
    case ready
    case running
    case failed
    case done
    case archived
}

public struct CursorTask: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var repositoryID: UUID
    public var title: String
    public var prompt: String
    public var autoCreatePR: Bool
    public var reasoningEffort: CursorReasoningEffort
    public var useFastModel: Bool
    public var harness: CursorHarness
    public var status: CursorTaskStatus
    public var createdAt: Date
    public var updatedAt: Date

    public static func new(
        id: UUID = UUID(),
        repositoryID: UUID,
        title: String,
        prompt: String,
        autoCreatePR: Bool = false,
        reasoningEffort: CursorReasoningEffort = .medium,
        useFastModel: Bool = false,
        harness: CursorHarness = .cursor,
        now: Date = Date()
    ) -> CursorTask {
        CursorTask(
            id: id,
            repositoryID: repositoryID,
            title: title,
            prompt: prompt,
            autoCreatePR: autoCreatePR,
            reasoningEffort: reasoningEffort,
            useFastModel: useFastModel,
            harness: harness,
            status: .ready,
            createdAt: now,
            updatedAt: now
        )
    }
}

public enum CursorTaskLifecycleError: Error, Equatable, LocalizedError, Sendable {
    case transitionNotAllowed
    case taskIsImmutable
    case taskAlreadyHasSuccessfulRun
    case hardDeleteNotAllowed

    public var errorDescription: String? {
        switch self {
        case .transitionNotAllowed:
            "This task cannot be moved to that state."
        case .taskIsImmutable:
            "This task can no longer be edited."
        case .taskAlreadyHasSuccessfulRun:
            "This task is already being sent or already has a Cursor run."
        case .hardDeleteNotAllowed:
            "Tasks can be archived, but not permanently deleted."
        }
    }
}

public enum CursorTaskLifecyclePolicy {
    public static func recordSuccessfulSend(for task: CursorTask, now: Date = Date()) throws -> CursorTask {
        guard task.status == .ready else {
            throw CursorTaskLifecycleError.transitionNotAllowed
        }

        return task.with(status: .running, now: now)
    }

    public static func recordFailedSend(for task: CursorTask, now: Date = Date()) throws -> CursorTask {
        guard task.status == .ready else {
            throw CursorTaskLifecycleError.transitionNotAllowed
        }

        return task.with(status: .failed, now: now)
    }

    public static func markDone(_ task: CursorTask, now: Date = Date()) throws -> CursorTask {
        guard task.status == .running else {
            throw CursorTaskLifecycleError.transitionNotAllowed
        }

        return task.with(status: .done, now: now)
    }

    public static func markFailed(_ task: CursorTask, now: Date = Date()) throws -> CursorTask {
        guard task.status == .running else {
            throw CursorTaskLifecycleError.transitionNotAllowed
        }

        return task.with(status: .failed, now: now)
    }

    public static func recoverForRetry(_ task: CursorTask, now: Date = Date()) throws -> CursorTask {
        guard task.status == .failed else {
            throw CursorTaskLifecycleError.transitionNotAllowed
        }

        return task.with(status: .ready, now: now)
    }

    public static func archive(_ task: CursorTask, now: Date = Date()) throws -> CursorTask {
        guard [.ready, .running, .failed, .done].contains(task.status) else {
            throw CursorTaskLifecycleError.transitionNotAllowed
        }

        return task.with(status: .archived, now: now)
    }

    public static func ensureEditable(_ task: CursorTask) throws {
        guard task.status == .ready else {
            throw CursorTaskLifecycleError.taskIsImmutable
        }
    }

    public static func ensureHardDeleteAllowed() throws {
        throw CursorTaskLifecycleError.hardDeleteNotAllowed
    }
}

private extension CursorTask {
    func with(status: CursorTaskStatus, now: Date) -> CursorTask {
        var copy = self
        copy.status = status
        copy.updatedAt = now
        return copy
    }
}
