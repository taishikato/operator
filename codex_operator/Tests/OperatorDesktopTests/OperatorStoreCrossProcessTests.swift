import Foundation
import Combine
import GRDB
import Testing
@testable import OperatorDesktop

@Test func storeOpensDatabaseInWALJournalMode() throws {
    let databaseURL = try temporaryDatabaseURL()
    _ = try OperatorStore(databaseURL: databaseURL)

    // Inspect the journal mode through an independent connection, the same
    // way a second process (the CLI) would observe it.
    let inspection = try DatabaseQueue(path: databaseURL.path)
    let journalMode = try inspection.read { db in
        try String.fetchOne(db, sql: "PRAGMA journal_mode")
    }
    #expect(journalMode?.lowercased() == "wal")
}

@Test func storeWriteSucceedsWhileAnotherConnectionHoldsAWriteTransaction() throws {
    let databaseURL = try temporaryDatabaseURL()
    let store = try OperatorStore(databaseURL: databaseURL)

    // A second connection simulates the other process (app vs CLI): SQLite
    // locking is per-connection, so contention behaves the same in-process.
    let competingConnection = try DatabaseQueue(path: databaseURL.path)
    let transactionHeld = DispatchSemaphore(value: 0)
    let holdDuration: TimeInterval = 0.5

    let holder = Thread {
        try? competingConnection.writeWithoutTransaction { db in
            try db.execute(sql: "BEGIN IMMEDIATE")
            try db.execute(
                sql: """
                    INSERT INTO repositories (id, name, path, defaultBranch, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, 0, 0)
                    """,
                arguments: [UUID().uuidString, "holder", "/tmp/holder", "main"]
            )
            transactionHeld.signal()
            Thread.sleep(forTimeInterval: holdDuration)
            try db.execute(sql: "COMMIT")
        }
    }
    holder.start()
    transactionHeld.wait()

    // Without a busy timeout this fails immediately with SQLITE_BUSY; with
    // one it blocks until the competing transaction commits, then succeeds.
    let repository = try store.createRepository(
        name: "concurrent",
        path: "/tmp/concurrent",
        defaultBranch: "main"
    )

    #expect(try store.repository(id: repository.id) != nil)
    #expect(try store.repositories().count == 2)
}

@Test func storePublishesChangesWhenAnotherConnectionCommits() throws {
    let databaseURL = try temporaryDatabaseURL()
    let store = try OperatorStore(databaseURL: databaseURL)
    let changeCounter = ChangeCounter()
    let cancellable = store.changes.sink {
        changeCounter.increment()
    }
    defer { cancellable.cancel() }

    store.startExternalChangeMonitoring(pollInterval: 0.05)
    defer { store.stopExternalChangeMonitoring() }

    let externalStore = try OperatorStore(databaseURL: databaseURL)
    _ = try externalStore.createRepository(
        name: "external",
        path: "/tmp/external",
        defaultBranch: "main"
    )

    let deadline = Date().addingTimeInterval(5)
    while changeCounter.count == 0, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.02)
    }
    #expect(changeCounter.count > 0)
}

@Test func externalChangeMonitoringIgnoresOwnWrites() throws {
    let databaseURL = try temporaryDatabaseURL()
    let store = try OperatorStore(databaseURL: databaseURL)
    let changeCounter = ChangeCounter()
    let cancellable = store.changes.sink {
        changeCounter.increment()
    }
    defer { cancellable.cancel() }

    store.startExternalChangeMonitoring(pollInterval: 0.05)
    defer { store.stopExternalChangeMonitoring() }

    _ = try store.createRepository(name: "own", path: "/tmp/own", defaultBranch: "main")

    // Give the poller several intervals to (incorrectly) report the store's
    // own write; only the direct publishChange should be observed.
    Thread.sleep(forTimeInterval: 0.3)
    #expect(changeCounter.count == 1)
}

private final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        value += 1
    }
}

private func temporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "OperatorStoreCrossProcessTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "operator.sqlite")
}
