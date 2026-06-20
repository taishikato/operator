import Foundation
import Testing
@testable import CursorOperatorCore

@Test func newCursorTaskDefaultsToReady() {
    let repositoryID = UUID()

    let task = CursorTask.new(
        repositoryID: repositoryID,
        title: "Implement persistence",
        prompt: "Add SQLite storage"
    )

    #expect(task.repositoryID == repositoryID)
    #expect(task.status == .ready)
}

@Test func lifecycleAllowsReadyToRunningToDoneToArchived() throws {
    let runningTask = try CursorTaskLifecyclePolicy.recordSuccessfulSend(for: readyTask())
    #expect(runningTask.status == .running)

    let doneTask = try CursorTaskLifecyclePolicy.markDone(runningTask)
    #expect(doneTask.status == .done)

    let archivedTask = try CursorTaskLifecyclePolicy.archive(doneTask)
    #expect(archivedTask.status == .archived)
}

@Test func failedSendLeavesTaskReady() throws {
    let failedTask = try CursorTaskLifecyclePolicy.recordFailedSend(for: readyTask())

    #expect(failedTask.status == .ready)
}

@Test func lifecycleAllowsRunningToFailedToArchived() throws {
    let runningTask = try CursorTaskLifecyclePolicy.recordSuccessfulSend(for: readyTask())
    let failedTask = try CursorTaskLifecyclePolicy.markFailed(runningTask)
    #expect(failedTask.status == .failed)

    let archivedTask = try CursorTaskLifecyclePolicy.archive(failedTask)
    #expect(archivedTask.status == .archived)
}

@Test func onlyReadyTasksAreEditable() {
    #expect(throws: Never.self) {
        try CursorTaskLifecyclePolicy.ensureEditable(readyTask())
    }

    for status in [CursorTaskStatus.running, .failed, .done, .archived] {
        #expect(throws: CursorTaskLifecycleError.taskIsImmutable) {
            try CursorTaskLifecyclePolicy.ensureEditable(task(status: status))
        }
    }
}

@Test func lifecycleRejectsInvalidTransitionsAndHardDelete() {
    #expect(throws: CursorTaskLifecycleError.transitionNotAllowed) {
        try CursorTaskLifecyclePolicy.markDone(readyTask())
    }
    #expect(throws: CursorTaskLifecycleError.transitionNotAllowed) {
        try CursorTaskLifecyclePolicy.markFailed(readyTask())
    }
    #expect(throws: CursorTaskLifecycleError.transitionNotAllowed) {
        try CursorTaskLifecyclePolicy.recordSuccessfulSend(for: task(status: .running))
    }
    #expect(throws: CursorTaskLifecycleError.transitionNotAllowed) {
        try CursorTaskLifecyclePolicy.archive(task(status: .archived))
    }
    #expect(throws: CursorTaskLifecycleError.hardDeleteNotAllowed) {
        try CursorTaskLifecyclePolicy.ensureHardDeleteAllowed()
    }
}

private func readyTask() -> CursorTask {
    task(status: .ready)
}

private func task(status: CursorTaskStatus) -> CursorTask {
    var task = CursorTask.new(
        repositoryID: UUID(),
        title: "Task",
        prompt: "Prompt"
    )
    task.status = status
    return task
}
