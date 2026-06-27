import Foundation
import GRDB

public struct CursorRepository: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let localPath: String
    public let githubURL: URL
    public let defaultBranch: String
    public let createdAt: Date
    public let updatedAt: Date
}

public enum CursorRunAttemptStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case failed
    case succeeded
}

public struct CursorRunAttempt: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let taskID: UUID
    public let repositoryID: UUID
    public let status: CursorRunAttemptStatus
    public let repositoryURL: URL
    public let startingRef: String
    public let model: String
    public let autoCreatePR: Bool
    public let prompt: String
    public let cursorAgentID: String?
    public let cursorRunID: String?
    public let cursorURL: URL?
    public let errorMessage: String?
    public let createdAt: Date
    public let completedAt: Date
}

public enum CursorOperatorStoreError: Error, Equatable, LocalizedError, Sendable {
    case repositoryNotFound
    case repositoryPathAlreadyRegistered(existingID: UUID)
    case taskNotFound
    case invalidStoredValue(String)

    public var errorDescription: String? {
        switch self {
        case .repositoryNotFound:
            "Repository not found."
        case .repositoryPathAlreadyRegistered:
            "This repository is already registered."
        case .taskNotFound:
            "Task not found."
        case .invalidStoredValue:
            "Stored data is invalid."
        }
    }
}

public final class CursorOperatorStore: @unchecked Sendable {
    private static let stalePendingSendAttemptMessage = "Previous Cursor send was interrupted before Cursor returned a run reference."

    private let dbQueue: DatabaseQueue

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        try Self.migrator.migrate(dbQueue)
    }

    public func createRepository(
        id: UUID = UUID(),
        name: String,
        localPath: String,
        githubURL: URL,
        defaultBranch: String,
        now: Date = Date()
    ) throws -> CursorRepository {
        try dbQueue.write { db in
            if let existingRepository = try repository(localPath: localPath, db: db) {
                throw CursorOperatorStoreError.repositoryPathAlreadyRegistered(existingID: existingRepository.id)
            }

            let repository = CursorRepository(
                id: id,
                name: name,
                localPath: localPath,
                githubURL: githubURL,
                defaultBranch: defaultBranch,
                createdAt: now,
                updatedAt: now
            )
            try db.execute(
                sql: """
                    INSERT INTO repositories (id, name, localPath, githubURL, defaultBranch, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    repository.id.uuidString,
                    repository.name,
                    repository.localPath,
                    repository.githubURL.absoluteString,
                    repository.defaultBranch,
                    repository.createdAt.storageValue,
                    repository.updatedAt.storageValue
                ]
            )
            return repository
        }
    }

    public func repositories() throws -> [CursorRepository] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM repositories ORDER BY createdAt, id")
                .map(Self.repository(from:))
        }
    }

    public func repository(id: UUID) throws -> CursorRepository? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM repositories WHERE id = ?", arguments: [id.uuidString])
                .map(Self.repository(from:))
        }
    }

    public func createTask(
        id: UUID = UUID(),
        repositoryID: UUID,
        title: String,
        prompt: String,
        autoCreatePR: Bool = false,
        reasoningEffort: CursorReasoningEffort = .medium,
        useFastModel: Bool = false,
        harness: CursorHarness = .cursor,
        now: Date = Date()
    ) throws -> CursorTask {
        try dbQueue.write { db in
            guard try repositoryExists(id: repositoryID, db: db) else {
                throw CursorOperatorStoreError.repositoryNotFound
            }

            let task = CursorTask.new(
                id: id,
                repositoryID: repositoryID,
                title: title,
                prompt: prompt,
                autoCreatePR: autoCreatePR,
                reasoningEffort: reasoningEffort,
                useFastModel: useFastModel,
                harness: harness,
                now: now
            )
            try insert(task: task, db: db)
            return task
        }
    }

    public func tasks() throws -> [CursorTask] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM tasks ORDER BY createdAt, id")
                .map(Self.task(from:))
        }
    }

    public func task(id: UUID) throws -> CursorTask? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM tasks WHERE id = ?", arguments: [id.uuidString])
                .map(Self.task(from:))
        }
    }

    public func updateTaskContent(
        id: UUID,
        title: String,
        prompt: String,
        autoCreatePR: Bool? = nil,
        reasoningEffort: CursorReasoningEffort? = nil,
        useFastModel: Bool? = nil,
        harness: CursorHarness? = nil,
        now: Date = Date()
    ) throws -> CursorTask {
        try dbQueue.write { db in
            var task = try requiredTask(id: id, db: db)
            try CursorTaskLifecyclePolicy.ensureEditable(task)
            task.title = title
            task.prompt = prompt
            if let autoCreatePR {
                task.autoCreatePR = autoCreatePR
            }
            if let reasoningEffort {
                task.reasoningEffort = reasoningEffort
            }
            if let useFastModel {
                task.useFastModel = useFastModel
            }
            if let harness {
                task.harness = harness
            }
            task.updatedAt = now
            try update(task: task, db: db)
            return task
        }
    }

    public func markTaskDone(id: UUID, now: Date = Date()) throws -> CursorTask {
        try updateTask(id: id) { task in
            try CursorTaskLifecyclePolicy.markDone(task, now: now)
        }
    }

    public func markTaskFailed(id: UUID, now: Date = Date()) throws -> CursorTask {
        try updateTask(id: id) { task in
            try CursorTaskLifecyclePolicy.markFailed(task, now: now)
        }
    }

    public func archiveTask(id: UUID, now: Date = Date()) throws -> CursorTask {
        try updateTask(id: id) { task in
            try CursorTaskLifecyclePolicy.archive(task, now: now)
        }
    }

    public func recoverTaskForRetry(id: UUID, now: Date = Date()) throws -> CursorTask {
        try updateTask(id: id) { task in
            try CursorTaskLifecyclePolicy.recoverForRetry(task, now: now)
        }
    }

    public func recordFailedSendAttempt(
        id: UUID = UUID(),
        taskID: UUID,
        repositoryURL: URL,
        startingRef: String,
        model: String,
        autoCreatePR: Bool,
        prompt: String,
        errorMessage: String,
        now: Date = Date()
    ) throws -> CursorRunAttempt {
        try dbQueue.write { db in
            let task = try CursorTaskLifecyclePolicy.recordFailedSend(for: requiredTask(id: taskID, db: db))
            try update(task: task, db: db)
            let attempt = CursorRunAttempt(
                id: id,
                taskID: task.id,
                repositoryID: task.repositoryID,
                status: .failed,
                repositoryURL: repositoryURL,
                startingRef: startingRef,
                model: model,
                autoCreatePR: autoCreatePR,
                prompt: prompt,
                cursorAgentID: nil,
                cursorRunID: nil,
                cursorURL: nil,
                errorMessage: errorMessage,
                createdAt: now,
                completedAt: now
            )
            try insert(runAttempt: attempt, db: db)
            return attempt
        }
    }

    public func claimSendAttempt(
        id: UUID = UUID(),
        taskID: UUID,
        repositoryURL: URL,
        startingRef: String,
        model: String,
        autoCreatePR: Bool,
        prompt: String,
        now: Date = Date(),
        stalePendingAge: TimeInterval = 10 * 60
    ) throws -> CursorRunAttempt {
        try dbQueue.write { db in
            let task = try requiredTask(id: taskID, db: db)
            _ = try CursorTaskLifecyclePolicy.recordFailedSend(for: task)
            try expireStalePendingSendAttempts(
                taskID: task.id,
                cutoff: now.addingTimeInterval(-stalePendingAge),
                now: now,
                db: db
            )
            guard try activeRunAttemptCount(taskID: task.id, db: db) == 0 else {
                throw CursorTaskLifecycleError.taskAlreadyHasSuccessfulRun
            }

            let attempt = CursorRunAttempt(
                id: id,
                taskID: task.id,
                repositoryID: task.repositoryID,
                status: .pending,
                repositoryURL: repositoryURL,
                startingRef: startingRef,
                model: model,
                autoCreatePR: autoCreatePR,
                prompt: prompt,
                cursorAgentID: nil,
                cursorRunID: nil,
                cursorURL: nil,
                errorMessage: nil,
                createdAt: now,
                completedAt: now
            )
            try insert(runAttempt: attempt, db: db)
            return attempt
        }
    }

    public func recordSuccessfulClaimedSendAttempt(
        id: UUID,
        cursorAgentID: String,
        cursorRunID: String,
        cursorURL: URL?,
        now: Date = Date()
    ) throws -> CursorRunAttempt {
        try dbQueue.write { db in
            let pendingAttempt = try requiredRunAttempt(id: id, db: db)
            guard pendingAttempt.status == .pending else {
                throw CursorTaskLifecycleError.taskAlreadyHasSuccessfulRun
            }
            let task = try requiredTask(id: pendingAttempt.taskID, db: db)
            let updatedTask = try CursorTaskLifecyclePolicy.recordSuccessfulSend(for: task, now: now)
            try update(task: updatedTask, db: db)

            let attempt = CursorRunAttempt(
                id: pendingAttempt.id,
                taskID: pendingAttempt.taskID,
                repositoryID: pendingAttempt.repositoryID,
                status: .succeeded,
                repositoryURL: pendingAttempt.repositoryURL,
                startingRef: pendingAttempt.startingRef,
                model: pendingAttempt.model,
                autoCreatePR: pendingAttempt.autoCreatePR,
                prompt: pendingAttempt.prompt,
                cursorAgentID: cursorAgentID,
                cursorRunID: cursorRunID,
                cursorURL: cursorURL,
                errorMessage: nil,
                createdAt: pendingAttempt.createdAt,
                completedAt: now
            )
            try update(runAttempt: attempt, db: db)
            return attempt
        }
    }

    public func recordRunFailure(
        taskID: UUID,
        runID: String,
        errorMessage: String,
        now: Date = Date()
    ) throws -> CursorRunAttempt {
        try dbQueue.write { db in
            let task = try requiredTask(id: taskID, db: db)
            let updatedTask = try CursorTaskLifecyclePolicy.markFailed(task, now: now)
            try update(task: updatedTask, db: db)

            let existingAttempt = try requiredSuccessfulRunAttempt(taskID: taskID, runID: runID, db: db)
            let attempt = CursorRunAttempt(
                id: existingAttempt.id,
                taskID: existingAttempt.taskID,
                repositoryID: existingAttempt.repositoryID,
                status: existingAttempt.status,
                repositoryURL: existingAttempt.repositoryURL,
                startingRef: existingAttempt.startingRef,
                model: existingAttempt.model,
                autoCreatePR: existingAttempt.autoCreatePR,
                prompt: existingAttempt.prompt,
                cursorAgentID: existingAttempt.cursorAgentID,
                cursorRunID: existingAttempt.cursorRunID,
                cursorURL: existingAttempt.cursorURL,
                errorMessage: errorMessage,
                createdAt: existingAttempt.createdAt,
                completedAt: now
            )
            try update(runAttempt: attempt, db: db)
            return attempt
        }
    }

    public func recordFailedClaimedSendAttempt(
        id: UUID,
        cursorAgentID: String? = nil,
        cursorRunID: String? = nil,
        cursorURL: URL? = nil,
        errorMessage: String,
        now: Date = Date()
    ) throws -> CursorRunAttempt {
        try dbQueue.write { db in
            let pendingAttempt = try requiredRunAttempt(id: id, db: db)
            guard pendingAttempt.status == .pending else {
                throw CursorTaskLifecycleError.transitionNotAllowed
            }
            let task = try requiredTask(id: pendingAttempt.taskID, db: db)
            let updatedTask = try CursorTaskLifecyclePolicy.recordFailedSend(for: task, now: now)
            try update(task: updatedTask, db: db)

            let attempt = CursorRunAttempt(
                id: pendingAttempt.id,
                taskID: pendingAttempt.taskID,
                repositoryID: pendingAttempt.repositoryID,
                status: .failed,
                repositoryURL: pendingAttempt.repositoryURL,
                startingRef: pendingAttempt.startingRef,
                model: pendingAttempt.model,
                autoCreatePR: pendingAttempt.autoCreatePR,
                prompt: pendingAttempt.prompt,
                cursorAgentID: cursorAgentID,
                cursorRunID: cursorRunID,
                cursorURL: cursorURL,
                errorMessage: errorMessage,
                createdAt: pendingAttempt.createdAt,
                completedAt: now
            )
            try update(runAttempt: attempt, db: db)
            return attempt
        }
    }

    public func recordSuccessfulSendAttempt(
        id: UUID = UUID(),
        taskID: UUID,
        repositoryURL: URL,
        startingRef: String,
        model: String,
        autoCreatePR: Bool,
        prompt: String,
        cursorAgentID: String,
        cursorRunID: String,
        cursorURL: URL?,
        now: Date = Date()
    ) throws -> CursorRunAttempt {
        try dbQueue.write { db in
            let task = try requiredTask(id: taskID, db: db)
            guard try successfulRunAttemptCount(taskID: task.id, db: db) == 0 else {
                throw CursorTaskLifecycleError.taskAlreadyHasSuccessfulRun
            }

            let updatedTask = try CursorTaskLifecyclePolicy.recordSuccessfulSend(for: task, now: now)
            try update(task: updatedTask, db: db)

            let attempt = CursorRunAttempt(
                id: id,
                taskID: task.id,
                repositoryID: task.repositoryID,
                status: .succeeded,
                repositoryURL: repositoryURL,
                startingRef: startingRef,
                model: model,
                autoCreatePR: autoCreatePR,
                prompt: prompt,
                cursorAgentID: cursorAgentID,
                cursorRunID: cursorRunID,
                cursorURL: cursorURL,
                errorMessage: nil,
                createdAt: now,
                completedAt: now
            )
            try insert(runAttempt: attempt, db: db)
            return attempt
        }
    }

    public func runAttempts(taskID: UUID) throws -> [CursorRunAttempt] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM runAttempts WHERE taskID = ? ORDER BY createdAt, id",
                arguments: [taskID.uuidString]
            )
            .map(Self.runAttempt(from:))
        }
    }

    private func updateTask(
        id: UUID,
        transform: (CursorTask) throws -> CursorTask
    ) throws -> CursorTask {
        try dbQueue.write { db in
            let task = try transform(requiredTask(id: id, db: db))
            try update(task: task, db: db)
            return task
        }
    }

    private func repositoryExists(id: UUID, db: Database) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM repositories WHERE id = ?",
            arguments: [id.uuidString]
        ) == 1
    }

    private func repository(localPath: String, db: Database) throws -> CursorRepository? {
        try Row.fetchOne(db, sql: "SELECT * FROM repositories WHERE localPath = ?", arguments: [localPath])
            .map(Self.repository(from:))
    }

    private func requiredTask(id: UUID, db: Database) throws -> CursorTask {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM tasks WHERE id = ?", arguments: [id.uuidString]) else {
            throw CursorOperatorStoreError.taskNotFound
        }
        return try Self.task(from: row)
    }

    private func requiredRunAttempt(id: UUID, db: Database) throws -> CursorRunAttempt {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM runAttempts WHERE id = ?", arguments: [id.uuidString]) else {
            throw CursorOperatorStoreError.taskNotFound
        }
        return try Self.runAttempt(from: row)
    }

    private func requiredSuccessfulRunAttempt(taskID: UUID, runID: String, db: Database) throws -> CursorRunAttempt {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM runAttempts WHERE taskID = ? AND cursorRunID = ? AND status = ?",
            arguments: [taskID.uuidString, runID, CursorRunAttemptStatus.succeeded.rawValue]
        ) else {
            throw CursorOperatorStoreError.taskNotFound
        }
        return try Self.runAttempt(from: row)
    }

    private func successfulRunAttemptCount(taskID: UUID, db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM runAttempts WHERE taskID = ? AND status = ?",
            arguments: [taskID.uuidString, CursorRunAttemptStatus.succeeded.rawValue]
        ) ?? 0
    }

    private func activeRunAttemptCount(taskID: UUID, db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM runAttempts WHERE taskID = ? AND status IN (?, ?)",
            arguments: [
                taskID.uuidString,
                CursorRunAttemptStatus.pending.rawValue,
                CursorRunAttemptStatus.succeeded.rawValue
            ]
        ) ?? 0
    }

    private func expireStalePendingSendAttempts(
        taskID: UUID,
        cutoff: Date,
        now: Date,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                UPDATE runAttempts
                SET status = ?, errorMessage = ?, completedAt = ?
                WHERE taskID = ? AND status = ? AND createdAt < ?
                """,
            arguments: [
                CursorRunAttemptStatus.failed.rawValue,
                Self.stalePendingSendAttemptMessage,
                now.storageValue,
                taskID.uuidString,
                CursorRunAttemptStatus.pending.rawValue,
                cutoff.storageValue
            ]
        )
    }

    private func insert(task: CursorTask, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO tasks (
                    id, repositoryID, title, prompt, autoCreatePR, reasoningEffort,
                    useFastModel, harness, status, createdAt, updatedAt
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                task.id.uuidString,
                task.repositoryID.uuidString,
                task.title,
                task.prompt,
                task.autoCreatePR,
                task.reasoningEffort.rawValue,
                task.useFastModel,
                task.harness.rawValue,
                task.status.rawValue,
                task.createdAt.storageValue,
                task.updatedAt.storageValue
            ]
        )
    }

    private func update(task: CursorTask, db: Database) throws {
        try db.execute(
            sql: """
                UPDATE tasks
                SET title = ?, prompt = ?, autoCreatePR = ?, reasoningEffort = ?,
                    useFastModel = ?, harness = ?, status = ?, updatedAt = ?
                WHERE id = ?
                """,
            arguments: [
                task.title,
                task.prompt,
                task.autoCreatePR,
                task.reasoningEffort.rawValue,
                task.useFastModel,
                task.harness.rawValue,
                task.status.rawValue,
                task.updatedAt.storageValue,
                task.id.uuidString
            ]
        )
    }

    private func insert(runAttempt: CursorRunAttempt, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO runAttempts (
                    id, taskID, repositoryID, status, repositoryURL, startingRef, model,
                    autoCreatePR, prompt, cursorAgentID, cursorRunID, cursorURL, errorMessage, createdAt, completedAt
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                runAttempt.id.uuidString,
                runAttempt.taskID.uuidString,
                runAttempt.repositoryID.uuidString,
                runAttempt.status.rawValue,
                runAttempt.repositoryURL.absoluteString,
                runAttempt.startingRef,
                runAttempt.model,
                runAttempt.autoCreatePR,
                runAttempt.prompt,
                runAttempt.cursorAgentID,
                runAttempt.cursorRunID,
                runAttempt.cursorURL?.absoluteString,
                runAttempt.errorMessage,
                runAttempt.createdAt.storageValue,
                runAttempt.completedAt.storageValue
            ]
        )
    }

    private func update(runAttempt: CursorRunAttempt, db: Database) throws {
        try db.execute(
            sql: """
                UPDATE runAttempts
                SET status = ?, cursorAgentID = ?, cursorRunID = ?, cursorURL = ?, errorMessage = ?, completedAt = ?
                WHERE id = ?
                """,
            arguments: [
                runAttempt.status.rawValue,
                runAttempt.cursorAgentID,
                runAttempt.cursorRunID,
                runAttempt.cursorURL?.absoluteString,
                runAttempt.errorMessage,
                runAttempt.completedAt.storageValue,
                runAttempt.id.uuidString
            ]
        )
    }
}

extension CursorOperatorStore {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createCursorOperatorMVPStore") { db in
            try db.create(table: "repositories") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("localPath", .text).notNull().unique()
                table.column("githubURL", .text).notNull()
                table.column("defaultBranch", .text).notNull()
                table.column("createdAt", .double).notNull()
                table.column("updatedAt", .double).notNull()
            }

            try db.create(table: "tasks") { table in
                table.column("id", .text).primaryKey()
                table.column("repositoryID", .text).notNull().references("repositories", onDelete: .restrict)
                table.column("title", .text).notNull()
                table.column("prompt", .text).notNull()
                table.column("status", .text).notNull()
                table.column("createdAt", .double).notNull()
                table.column("updatedAt", .double).notNull()
            }

            try db.create(table: "runAttempts") { table in
                table.column("id", .text).primaryKey()
                table.column("taskID", .text).notNull().references("tasks", onDelete: .restrict)
                table.column("repositoryID", .text).notNull().references("repositories", onDelete: .restrict)
                table.column("status", .text).notNull()
                table.column("repositoryURL", .text).notNull()
                table.column("startingRef", .text).notNull()
                table.column("model", .text).notNull()
                table.column("autoCreatePR", .boolean).notNull()
                table.column("prompt", .text).notNull()
                table.column("cursorAgentID", .text)
                table.column("cursorURL", .text)
                table.column("errorMessage", .text)
                table.column("createdAt", .double).notNull()
                table.column("completedAt", .double).notNull()
            }

            try db.create(index: "tasks_on_repositoryID", on: "tasks", columns: ["repositoryID"])
            try db.create(index: "runAttempts_on_taskID", on: "runAttempts", columns: ["taskID"])
            try db.execute(sql: "CREATE UNIQUE INDEX runAttempts_one_success_per_task ON runAttempts(taskID) WHERE status = 'succeeded'")
        }

        migrator.registerMigration("addTaskAutoCreatePR") { db in
            try db.alter(table: "tasks") { table in
                table.add(column: "autoCreatePR", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("addCursorRunIDToRunAttempts") { db in
            try db.alter(table: "runAttempts") { table in
                table.add(column: "cursorRunID", .text)
            }
        }

        migrator.registerMigration("addActiveSendAttemptGuard") { db in
            try db.execute(sql: "CREATE UNIQUE INDEX runAttempts_one_active_send_per_task ON runAttempts(taskID) WHERE status IN ('pending', 'succeeded')")
        }

        migrator.registerMigration("addTaskHarnessConfiguration") { db in
            try db.alter(table: "tasks") { table in
                table.add(column: "reasoningEffort", .text)
                    .notNull()
                    .defaults(to: CursorReasoningEffort.medium.rawValue)
                table.add(column: "useFastModel", .boolean).notNull().defaults(to: false)
                table.add(column: "harness", .text)
                    .notNull()
                    .defaults(to: CursorHarness.cursor.rawValue)
            }
        }

        return migrator
    }

    private static func repository(from row: Row) throws -> CursorRepository {
        guard let githubURL = URL(string: row["githubURL"]) else {
            throw CursorOperatorStoreError.invalidStoredValue("githubURL")
        }

        return CursorRepository(
            id: try uuid(row["id"]),
            name: row["name"],
            localPath: row["localPath"],
            githubURL: githubURL,
            defaultBranch: row["defaultBranch"],
            createdAt: Date(storageValue: row["createdAt"]),
            updatedAt: Date(storageValue: row["updatedAt"])
        )
    }

    private static func task(from row: Row) throws -> CursorTask {
        guard let status = CursorTaskStatus(rawValue: row["status"]) else {
            throw CursorOperatorStoreError.invalidStoredValue("status")
        }
        guard let reasoningEffort = CursorReasoningEffort(rawValue: row["reasoningEffort"]) else {
            throw CursorOperatorStoreError.invalidStoredValue("reasoningEffort")
        }
        guard let harness = CursorHarness(rawValue: row["harness"]) else {
            throw CursorOperatorStoreError.invalidStoredValue("harness")
        }

        return CursorTask(
            id: try uuid(row["id"]),
            repositoryID: try uuid(row["repositoryID"]),
            title: row["title"],
            prompt: row["prompt"],
            autoCreatePR: row["autoCreatePR"],
            reasoningEffort: reasoningEffort,
            useFastModel: row["useFastModel"],
            harness: harness,
            status: status,
            createdAt: Date(storageValue: row["createdAt"]),
            updatedAt: Date(storageValue: row["updatedAt"])
        )
    }

    private static func runAttempt(from row: Row) throws -> CursorRunAttempt {
        guard let status = CursorRunAttemptStatus(rawValue: row["status"]) else {
            throw CursorOperatorStoreError.invalidStoredValue("status")
        }
        guard let repositoryURL = URL(string: row["repositoryURL"]) else {
            throw CursorOperatorStoreError.invalidStoredValue("repositoryURL")
        }
        let cursorURLString: String? = row["cursorURL"]

        return CursorRunAttempt(
            id: try uuid(row["id"]),
            taskID: try uuid(row["taskID"]),
            repositoryID: try uuid(row["repositoryID"]),
            status: status,
            repositoryURL: repositoryURL,
            startingRef: row["startingRef"],
            model: row["model"],
            autoCreatePR: row["autoCreatePR"],
            prompt: row["prompt"],
            cursorAgentID: row["cursorAgentID"],
            cursorRunID: row["cursorRunID"],
            cursorURL: cursorURLString.flatMap(URL.init(string:)),
            errorMessage: row["errorMessage"],
            createdAt: Date(storageValue: row["createdAt"]),
            completedAt: Date(storageValue: row["completedAt"])
        )
    }

    private static func uuid(_ value: String) throws -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            throw CursorOperatorStoreError.invalidStoredValue("UUID")
        }
        return uuid
    }
}

private extension Date {
    var storageValue: Double {
        timeIntervalSince1970
    }

    init(storageValue: Double) {
        self = Date(timeIntervalSince1970: storageValue)
    }
}
