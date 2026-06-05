import Foundation
import GRDB

public struct OperatorRepository: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let path: String
    public let defaultBranch: String
    public let createdAt: Date
    public let updatedAt: Date
}

public enum RunStatus: String, Codable, CaseIterable, Sendable {
    case triggerFailed
    case triggered
}

public struct OperatorRun: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let taskID: UUID
    public let repositoryID: UUID
    public let status: RunStatus
    public let worktreePath: String
    public let baseBranch: String
    public let baseRef: String
    public let codexThreadID: String?
    public let codexThreadURL: URL?
    public let errorMessage: String?
    public let createdAt: Date
    public let completedAt: Date?
}

public enum OperatorStoreError: Error, Equatable, LocalizedError, Sendable {
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

public final class OperatorStore: @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        dbQueue = try DatabaseQueue(path: databaseURL.path)
        try Self.migrator.migrate(dbQueue)
    }

    public static func applicationSupportStore(
        fileManager: FileManager = .default
    ) throws -> OperatorStore {
        try OperatorStore(databaseURL: applicationSupportDatabaseURL(fileManager: fileManager))
    }

    public static func applicationSupportDatabaseURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL
            .appending(path: "Operator", directoryHint: .isDirectory)
            .appending(path: "operator.sqlite")
    }

    public func createRepository(
        id: UUID = UUID(),
        name: String,
        path: String,
        defaultBranch: String,
        now: Date = Date()
    ) throws -> OperatorRepository {
        try dbQueue.write { db in
            if let existingRepository = try repository(path: path, db: db) {
                throw OperatorStoreError.repositoryPathAlreadyRegistered(existingID: existingRepository.id)
            }

            let repository = OperatorRepository(
                id: id,
                name: name,
                path: path,
                defaultBranch: defaultBranch,
                createdAt: now,
                updatedAt: now
            )
            try db.execute(
                sql: """
                    INSERT INTO repositories (id, name, path, defaultBranch, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    repository.id.uuidString,
                    repository.name,
                    repository.path,
                    repository.defaultBranch,
                    repository.createdAt.storageValue,
                    repository.updatedAt.storageValue
                ]
            )
            return repository
        }
    }

    public func repositories() throws -> [OperatorRepository] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM repositories ORDER BY createdAt, id")
                .map(Self.repository(from:))
        }
    }

    public func updateRepositoryDefaultBranch(
        id: UUID,
        defaultBranch: String,
        now: Date = Date()
    ) throws -> OperatorRepository {
        try dbQueue.write { db in
            let repository = try requiredRepository(id: id, db: db)
            let updatedRepository = OperatorRepository(
                id: repository.id,
                name: repository.name,
                path: repository.path,
                defaultBranch: defaultBranch,
                createdAt: repository.createdAt,
                updatedAt: now
            )

            try db.execute(
                sql: """
                    UPDATE repositories
                    SET defaultBranch = ?, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [
                    updatedRepository.defaultBranch,
                    updatedRepository.updatedAt.storageValue,
                    updatedRepository.id.uuidString
                ]
            )

            return updatedRepository
        }
    }

    public func createTask(
        id: UUID = UUID(),
        repositoryID: UUID,
        title: String,
        prompt: String,
        reasoningEffort: ReasoningEffort = .medium,
        now: Date = Date()
    ) throws -> OperatorTask {
        try dbQueue.write { db in
            guard try repositoryExists(id: repositoryID, db: db) else {
                throw OperatorStoreError.repositoryNotFound
            }

            let task = OperatorTask.new(
                id: id,
                repositoryID: repositoryID,
                title: title,
                prompt: prompt,
                reasoningEffort: reasoningEffort,
                now: now
            )

            try insert(task: task, db: db)
            return task
        }
    }

    public func tasks() throws -> [OperatorTask] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM tasks ORDER BY createdAt, id")
                .map(Self.task(from:))
        }
    }

    public func task(id: UUID) throws -> OperatorTask? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM tasks WHERE id = ?", arguments: [id.uuidString])
                .map(Self.task(from:))
        }
    }

    public func updateTaskContent(
        id: UUID,
        title: String,
        prompt: String,
        reasoningEffort: ReasoningEffort,
        now: Date = Date()
    ) throws -> OperatorTask {
        try dbQueue.write { db in
            var task = try requiredTask(id: id, db: db)
            try TaskLifecyclePolicy.ensureEditable(task)

            task.title = title
            task.prompt = prompt
            task.reasoningEffort = reasoningEffort
            task.updatedAt = now
            try update(task: task, db: db)
            return task
        }
    }

    public func archiveTask(id: UUID, now: Date = Date()) throws -> OperatorTask {
        try updateTask(id: id) { task in
            try TaskLifecyclePolicy.archive(task, now: now)
        }
    }

    public func markTaskDone(id: UUID, now: Date = Date()) throws -> OperatorTask {
        try updateTask(id: id) { task in
            try TaskLifecyclePolicy.moveToDone(task, now: now)
        }
    }

    public func assertTaskReady(id: UUID) throws -> OperatorTask {
        try dbQueue.read { db in
            let task = try requiredTask(id: id, db: db)
            return try TaskLifecyclePolicy.moveToReady(task)
        }
    }

    public func recordFailedRun(
        id: UUID = UUID(),
        taskID: UUID,
        worktreePath: String,
        baseBranch: String,
        baseRef: String,
        errorMessage: String,
        now: Date = Date()
    ) throws -> OperatorRun {
        try dbQueue.write { db in
            let task = try TaskLifecyclePolicy.recordFailedRun(for: requiredTask(id: taskID, db: db))
            let run = OperatorRun(
                id: id,
                taskID: task.id,
                repositoryID: task.repositoryID,
                status: .triggerFailed,
                worktreePath: worktreePath,
                baseBranch: baseBranch,
                baseRef: baseRef,
                codexThreadID: nil,
                codexThreadURL: nil,
                errorMessage: errorMessage,
                createdAt: now,
                completedAt: now
            )
            try insert(run: run, db: db)
            return run
        }
    }

    public func recordSuccessfulRun(
        id: UUID = UUID(),
        taskID: UUID,
        worktreePath: String,
        baseBranch: String,
        baseRef: String,
        codexThreadID: String,
        codexThreadURL: URL?,
        now: Date = Date()
    ) throws -> OperatorRun {
        try dbQueue.write { db in
            let task = try requiredTask(id: taskID, db: db)
            guard try successfulRunCount(taskID: task.id, db: db) == 0 else {
                throw TaskLifecycleError.taskAlreadyHasSuccessfulRun
            }

            let updatedTask = try TaskLifecyclePolicy.recordSuccessfulRun(for: task, now: now)
            try update(task: updatedTask, db: db)

            let run = OperatorRun(
                id: id,
                taskID: task.id,
                repositoryID: task.repositoryID,
                status: .triggered,
                worktreePath: worktreePath,
                baseBranch: baseBranch,
                baseRef: baseRef,
                codexThreadID: codexThreadID,
                codexThreadURL: codexThreadURL,
                errorMessage: nil,
                createdAt: now,
                completedAt: now
            )
            try insert(run: run, db: db)
            return run
        }
    }

    public func runs(taskID: UUID) throws -> [OperatorRun] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM runs WHERE taskID = ? ORDER BY createdAt, id",
                arguments: [taskID.uuidString]
            )
            .map(Self.run(from:))
        }
    }

    private func updateTask(
        id: UUID,
        transform: (OperatorTask) throws -> OperatorTask
    ) throws -> OperatorTask {
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

    private func requiredRepository(id: UUID, db: Database) throws -> OperatorRepository {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM repositories WHERE id = ?", arguments: [id.uuidString]) else {
            throw OperatorStoreError.repositoryNotFound
        }
        return try Self.repository(from: row)
    }

    private func repository(path: String, db: Database) throws -> OperatorRepository? {
        try Row.fetchOne(db, sql: "SELECT * FROM repositories WHERE path = ?", arguments: [path])
            .map(Self.repository(from:))
    }

    private func requiredTask(id: UUID, db: Database) throws -> OperatorTask {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM tasks WHERE id = ?", arguments: [id.uuidString]) else {
            throw OperatorStoreError.taskNotFound
        }
        return try Self.task(from: row)
    }

    private func successfulRunCount(taskID: UUID, db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM runs WHERE taskID = ? AND status = ?",
            arguments: [taskID.uuidString, RunStatus.triggered.rawValue]
        ) ?? 0
    }

    private func insert(task: OperatorTask, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO tasks (
                    id, repositoryID, title, prompt, reasoningEffort, status, createdAt, updatedAt
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: task.databaseArguments
        )
    }

    private func update(task: OperatorTask, db: Database) throws {
        try db.execute(
            sql: """
                UPDATE tasks
                SET title = ?, prompt = ?, reasoningEffort = ?, status = ?, updatedAt = ?
                WHERE id = ?
                """,
            arguments: [
                task.title,
                task.prompt,
                task.reasoningEffort.rawValue,
                task.status.rawValue,
                task.updatedAt.storageValue,
                task.id.uuidString
            ]
        )
    }

    private func insert(run: OperatorRun, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO runs (
                    id, taskID, repositoryID, status, worktreePath, baseBranch, baseRef,
                    codexThreadID, codexThreadURL, errorMessage, createdAt, completedAt
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                run.id.uuidString,
                run.taskID.uuidString,
                run.repositoryID.uuidString,
                run.status.rawValue,
                run.worktreePath,
                run.baseBranch,
                run.baseRef,
                run.codexThreadID,
                run.codexThreadURL?.absoluteString,
                run.errorMessage,
                run.createdAt.storageValue,
                run.completedAt?.storageValue
            ]
        )
    }
}

private extension OperatorStore {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createOperatorDesktopMVPStore") { db in
            try db.create(table: "repositories") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("path", .text).notNull()
                table.column("defaultBranch", .text).notNull()
                table.column("createdAt", .double).notNull()
                table.column("updatedAt", .double).notNull()
            }

            try db.create(table: "tasks") { table in
                table.column("id", .text).primaryKey()
                table.column("repositoryID", .text).notNull().references("repositories", onDelete: .restrict)
                table.column("title", .text).notNull()
                table.column("prompt", .text).notNull()
                table.column("reasoningEffort", .text).notNull()
                table.column("status", .text).notNull()
                table.column("createdAt", .double).notNull()
                table.column("updatedAt", .double).notNull()
            }

            try db.create(table: "runs") { table in
                table.column("id", .text).primaryKey()
                table.column("taskID", .text).notNull().references("tasks", onDelete: .restrict)
                table.column("repositoryID", .text).notNull().references("repositories", onDelete: .restrict)
                table.column("status", .text).notNull()
                table.column("worktreePath", .text).notNull()
                table.column("baseBranch", .text).notNull()
                table.column("baseRef", .text).notNull()
                table.column("codexThreadID", .text)
                table.column("codexThreadURL", .text)
                table.column("errorMessage", .text)
                table.column("createdAt", .double).notNull()
                table.column("completedAt", .double)
            }

            try db.create(index: "tasks_on_repositoryID", on: "tasks", columns: ["repositoryID"])
            try db.create(index: "runs_on_taskID", on: "runs", columns: ["taskID"])
            // Keep this predicate aligned with RunStatus.triggered.rawValue.
            try db.execute(sql: "CREATE UNIQUE INDEX runs_one_success_per_task ON runs(taskID) WHERE status = 'triggered'")
        }

        migrator.registerMigration("addUniqueRepositoryPathIndex") { db in
            try db.create(index: "repositories_on_path", on: "repositories", columns: ["path"], unique: true)
        }

        return migrator
    }

    static func repository(from row: Row) throws -> OperatorRepository {
        OperatorRepository(
            id: try uuid(row["id"]),
            name: row["name"],
            path: row["path"],
            defaultBranch: row["defaultBranch"],
            createdAt: Date(storageValue: row["createdAt"]),
            updatedAt: Date(storageValue: row["updatedAt"])
        )
    }

    static func task(from row: Row) throws -> OperatorTask {
        guard let reasoningEffort = ReasoningEffort(rawValue: row["reasoningEffort"]) else {
            throw OperatorStoreError.invalidStoredValue("reasoningEffort")
        }
        guard let status = TaskStatus(rawValue: row["status"]) else {
            throw OperatorStoreError.invalidStoredValue("status")
        }

        return OperatorTask(
            id: try uuid(row["id"]),
            repositoryID: try uuid(row["repositoryID"]),
            title: row["title"],
            prompt: row["prompt"],
            reasoningEffort: reasoningEffort,
            status: status,
            createdAt: Date(storageValue: row["createdAt"]),
            updatedAt: Date(storageValue: row["updatedAt"])
        )
    }

    static func run(from row: Row) throws -> OperatorRun {
        guard let status = RunStatus(rawValue: row["status"]) else {
            throw OperatorStoreError.invalidStoredValue("status")
        }

        let urlString: String? = row["codexThreadURL"]
        return OperatorRun(
            id: try uuid(row["id"]),
            taskID: try uuid(row["taskID"]),
            repositoryID: try uuid(row["repositoryID"]),
            status: status,
            worktreePath: row["worktreePath"],
            baseBranch: row["baseBranch"],
            baseRef: row["baseRef"],
            codexThreadID: row["codexThreadID"],
            codexThreadURL: urlString.flatMap(URL.init(string:)),
            errorMessage: row["errorMessage"],
            createdAt: Date(storageValue: row["createdAt"]),
            completedAt: Date(optionalStorageValue: row["completedAt"])
        )
    }

    static func uuid(_ value: String) throws -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            throw OperatorStoreError.invalidStoredValue("UUID")
        }
        return uuid
    }
}

private extension OperatorTask {
    var databaseArguments: StatementArguments {
        [
            id.uuidString,
            repositoryID.uuidString,
            title,
            prompt,
            reasoningEffort.rawValue,
            status.rawValue,
            createdAt.storageValue,
            updatedAt.storageValue
        ]
    }
}

private extension Date {
    var storageValue: Double {
        timeIntervalSince1970
    }

    init(storageValue: Double) {
        self = Date(timeIntervalSince1970: storageValue)
    }

    init?(optionalStorageValue: Double?) {
        guard let optionalStorageValue else {
            return nil
        }
        self = Date(storageValue: optionalStorageValue)
    }
}
