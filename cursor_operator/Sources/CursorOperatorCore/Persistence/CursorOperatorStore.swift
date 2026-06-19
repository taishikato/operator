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
        now: Date = Date()
    ) throws -> CursorTask {
        try dbQueue.write { db in
            var task = try requiredTask(id: id, db: db)
            try CursorTaskLifecyclePolicy.ensureEditable(task)
            task.title = title
            task.prompt = prompt
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

    public func archiveTask(id: UUID, now: Date = Date()) throws -> CursorTask {
        try updateTask(id: id) { task in
            try CursorTaskLifecyclePolicy.archive(task, now: now)
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
                cursorURL: nil,
                errorMessage: errorMessage,
                createdAt: now,
                completedAt: now
            )
            try insert(runAttempt: attempt, db: db)
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
        cursorURL: URL,
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

    private func successfulRunAttemptCount(taskID: UUID, db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM runAttempts WHERE taskID = ? AND status = ?",
            arguments: [taskID.uuidString, CursorRunAttemptStatus.succeeded.rawValue]
        ) ?? 0
    }

    private func insert(task: CursorTask, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO tasks (id, repositoryID, title, prompt, status, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                task.id.uuidString,
                task.repositoryID.uuidString,
                task.title,
                task.prompt,
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
                SET title = ?, prompt = ?, status = ?, updatedAt = ?
                WHERE id = ?
                """,
            arguments: [
                task.title,
                task.prompt,
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
                    autoCreatePR, prompt, cursorAgentID, cursorURL, errorMessage, createdAt, completedAt
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                runAttempt.cursorURL?.absoluteString,
                runAttempt.errorMessage,
                runAttempt.createdAt.storageValue,
                runAttempt.completedAt.storageValue
            ]
        )
    }
}

private extension CursorOperatorStore {
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

        return migrator
    }

    static func repository(from row: Row) throws -> CursorRepository {
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

    static func task(from row: Row) throws -> CursorTask {
        guard let status = CursorTaskStatus(rawValue: row["status"]) else {
            throw CursorOperatorStoreError.invalidStoredValue("status")
        }

        return CursorTask(
            id: try uuid(row["id"]),
            repositoryID: try uuid(row["repositoryID"]),
            title: row["title"],
            prompt: row["prompt"],
            status: status,
            createdAt: Date(storageValue: row["createdAt"]),
            updatedAt: Date(storageValue: row["updatedAt"])
        )
    }

    static func runAttempt(from row: Row) throws -> CursorRunAttempt {
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
            cursorURL: cursorURLString.flatMap(URL.init(string:)),
            errorMessage: row["errorMessage"],
            createdAt: Date(storageValue: row["createdAt"]),
            completedAt: Date(storageValue: row["completedAt"])
        )
    }

    static func uuid(_ value: String) throws -> UUID {
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
