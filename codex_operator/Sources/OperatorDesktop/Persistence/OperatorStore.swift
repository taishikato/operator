import Foundation
import Combine
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
    case running
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
    /// PID of the process that triggered the run (app or operator CLI).
    /// Nil on terminal rows and rows recorded before ownership existed.
    public let ownerPID: Int32?
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
    private let changeSubject = PassthroughSubject<Void, Never>()
    private let monitorLock = NSLock()
    private var monitorTask: Task<Void, Never>?

    public var changes: AnyPublisher<Void, Never> {
        changeSubject.eraseToAnyPublisher()
    }

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // The app and the operator CLI share this database from separate
        // processes: wait out a competing writer instead of failing with
        // SQLITE_BUSY, and use WAL so readers don't block the writer.
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        try Self.migrator.migrate(dbQueue)
    }

    deinit {
        monitorTask?.cancel()
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
        let createdRepository = try dbQueue.write { db in
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
        publishChange()
        return createdRepository
    }

    public func repositories() throws -> [OperatorRepository] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM repositories ORDER BY createdAt, id")
                .map(Self.repository(from:))
        }
    }

    public func repository(id: UUID) throws -> OperatorRepository? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM repositories WHERE id = ?", arguments: [id.uuidString])
                .map(Self.repository(from:))
        }
    }

    public func updateRepositoryDefaultBranch(
        id: UUID,
        defaultBranch: String,
        now: Date = Date()
    ) throws -> OperatorRepository {
        let repository = try dbQueue.write { db in
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
        publishChange()
        return repository
    }

    public func createTask(
        id: UUID = UUID(),
        repositoryID: UUID,
        title: String,
        prompt: String,
        reasoningEffort: ReasoningEffort = .medium,
        now: Date = Date()
    ) throws -> OperatorTask {
        let task = try dbQueue.write { db in
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
        publishChange()
        return task
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
        let task = try dbQueue.write { db in
            var task = try requiredTask(id: id, db: db)
            try TaskLifecyclePolicy.ensureEditable(task)

            task.title = title
            task.prompt = prompt
            task.reasoningEffort = reasoningEffort
            task.updatedAt = now
            try update(task: task, db: db)
            return task
        }
        publishChange()
        return task
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
        let run = try dbQueue.write { db in
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
                ownerPID: nil,
                createdAt: now,
                completedAt: now
            )
            try insert(run: run, db: db)
            return run
        }
        publishChange()
        return run
    }

    public func recordStartedRun(
        id: UUID = UUID(),
        taskID: UUID,
        worktreePath: String,
        baseBranch: String,
        baseRef: String,
        codexThreadID: String,
        codexThreadURL: URL?,
        ownerPID: Int32? = ProcessInfo.processInfo.processIdentifier,
        now: Date = Date()
    ) throws -> OperatorRun {
        let run = try dbQueue.write { db in
            let task = try requiredTask(id: taskID, db: db)
            guard try activeRunCount(taskID: task.id, db: db) == 0 else {
                throw TaskLifecycleError.taskAlreadyHasSuccessfulRun
            }

            let updatedTask = try TaskLifecyclePolicy.recordSuccessfulRun(for: task, now: now)
            try update(task: updatedTask, db: db)

            let run = OperatorRun(
                id: id,
                taskID: task.id,
                repositoryID: task.repositoryID,
                status: .running,
                worktreePath: worktreePath,
                baseBranch: baseBranch,
                baseRef: baseRef,
                codexThreadID: codexThreadID,
                codexThreadURL: codexThreadURL,
                errorMessage: nil,
                ownerPID: ownerPID,
                createdAt: now,
                completedAt: nil
            )
            try insert(run: run, db: db)
            return run
        }
        publishChange()
        return run
    }

    public func completeStartedRun(id: UUID, now: Date = Date()) throws -> OperatorRun {
        let run = try dbQueue.write { db in
            let currentRun = try requiredRun(id: id, db: db)
            guard currentRun.status == .running else {
                return currentRun
            }
            let completedRun = OperatorRun(
                id: currentRun.id,
                taskID: currentRun.taskID,
                repositoryID: currentRun.repositoryID,
                status: .triggered,
                worktreePath: currentRun.worktreePath,
                baseBranch: currentRun.baseBranch,
                baseRef: currentRun.baseRef,
                codexThreadID: currentRun.codexThreadID,
                codexThreadURL: currentRun.codexThreadURL,
                errorMessage: currentRun.errorMessage,
                ownerPID: currentRun.ownerPID,
                createdAt: currentRun.createdAt,
                completedAt: now
            )
            try db.execute(
                sql: """
                    UPDATE runs
                    SET status = ?, completedAt = ?
                    WHERE id = ?
                    """,
                arguments: [
                    completedRun.status.rawValue,
                    completedRun.completedAt?.storageValue,
                    completedRun.id.uuidString
                ]
            )

            // Surface the finished turn by advancing the task into Done so the
            // enabled "Open in Codex App" action lives in the Done column.
            let task = try requiredTask(id: completedRun.taskID, db: db)
            if task.status == .review {
                try update(task: TaskLifecyclePolicy.moveToDone(task, now: now), db: db)
            }
            return completedRun
        }
        publishChange()
        return run
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
        let run = try dbQueue.write { db in
            let task = try requiredTask(id: taskID, db: db)
            guard try activeRunCount(taskID: task.id, db: db) == 0 else {
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
                ownerPID: nil,
                createdAt: now,
                completedAt: now
            )
            try insert(run: run, db: db)
            return run
        }
        publishChange()
        return run
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

    public func runningRuns() throws -> [OperatorRun] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM runs WHERE status = ? ORDER BY createdAt, id",
                arguments: [RunStatus.running.rawValue]
            )
            .map(Self.run(from:))
        }
    }

    public func latestRunsByTaskID() throws -> [UUID: OperatorRun] {
        try dbQueue.read { db in
            let runs = try Row.fetchAll(db, sql: "SELECT * FROM runs ORDER BY taskID, createdAt, id")
                .map(Self.run(from:))
            var latestRuns: [UUID: OperatorRun] = [:]
            for run in runs {
                latestRuns[run.taskID] = run
            }
            return latestRuns
        }
    }

    private func updateTask(
        id: UUID,
        transform: (OperatorTask) throws -> OperatorTask
    ) throws -> OperatorTask {
        let task = try dbQueue.write { db in
            let task = try transform(requiredTask(id: id, db: db))
            try update(task: task, db: db)
            return task
        }
        publishChange()
        return task
    }

    /// Fires `changes` when another connection (e.g. the operator CLI in a
    /// separate process) commits to the database. `PRAGMA data_version` only
    /// moves for foreign commits, so this never double-reports the store's
    /// own writes.
    public func startExternalChangeMonitoring(pollInterval: TimeInterval = 2.0) {
        monitorLock.lock()
        defer { monitorLock.unlock() }
        guard monitorTask == nil else {
            return
        }

        // Capture the baseline synchronously so commits landing right after
        // this call cannot slip under the monitor's first reading.
        let baseline = currentDataVersion()
        monitorTask = Task { [weak self] in
            var lastVersion = baseline
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                guard let self, !Task.isCancelled else {
                    return
                }
                guard let version = self.currentDataVersion() else {
                    continue
                }
                if let previousVersion = lastVersion, version != previousVersion {
                    self.publishChange()
                }
                lastVersion = version
            }
        }
    }

    public func stopExternalChangeMonitoring() {
        monitorLock.lock()
        defer { monitorLock.unlock() }
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func currentDataVersion() -> Int? {
        try? dbQueue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA data_version")
        }
    }

    private func publishChange() {
        changeSubject.send(())
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

    private func requiredRun(id: UUID, db: Database) throws -> OperatorRun {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM runs WHERE id = ?", arguments: [id.uuidString]) else {
            throw OperatorStoreError.invalidStoredValue("run")
        }
        return try Self.run(from: row)
    }

    private func activeRunCount(taskID: UUID, db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM runs WHERE taskID = ? AND status IN (?, ?)",
            arguments: [taskID.uuidString, RunStatus.running.rawValue, RunStatus.triggered.rawValue]
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
                    codexThreadID, codexThreadURL, errorMessage, ownerPID, createdAt, completedAt
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                run.ownerPID,
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
            // Keep this predicate aligned with active run statuses.
            try db.execute(sql: "CREATE UNIQUE INDEX runs_one_success_per_task ON runs(taskID) WHERE status IN ('running', 'triggered')")
        }

        migrator.registerMigration("addUniqueRepositoryPathIndex") { db in
            try db.create(index: "repositories_on_path", on: "repositories", columns: ["path"], unique: true)
        }

        migrator.registerMigration("includeRunningRunsInActiveRunIndex") { db in
            try db.execute(sql: "DROP INDEX runs_one_success_per_task")
            try db.execute(sql: "CREATE UNIQUE INDEX runs_one_success_per_task ON runs(taskID) WHERE status IN ('running', 'triggered')")
        }

        // Nullable so rows recorded before run ownership existed stay valid
        // and keep being treated as recoverable orphans.
        migrator.registerMigration("addRunOwnerPID") { db in
            try db.alter(table: "runs") { table in
                table.add(column: "ownerPID", .integer)
            }
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
            ownerPID: row["ownerPID"],
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
