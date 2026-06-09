import Foundation
import Testing
@testable import OperatorDesktop

@Test func newTaskDraftsDefaultToReadyWithMediumReasoning() throws {
    let repositoryID = UUID()

    let task = OperatorTask.new(
        repositoryID: repositoryID,
        title: "Implement issue 2",
        prompt: "Add persistence"
    )

    #expect(task.repositoryID == repositoryID)
    #expect(task.status == .ready)
    #expect(task.reasoningEffort == .medium)
}

@Test func lifecycleAllowsMVPForwardTransitions() throws {
    let sentTask = try TaskLifecyclePolicy.recordSuccessfulRun(for: readyTask())
    #expect(sentTask.status == .review)

    let doneTask = try TaskLifecyclePolicy.moveToDone(sentTask)
    #expect(doneTask.status == .done)

    let archivedTask = try TaskLifecyclePolicy.archive(doneTask)
    #expect(archivedTask.status == .archived)
}

@Test func failedRunLeavesTaskReady() throws {
    let task = readyTask()

    let failedTask = try TaskLifecyclePolicy.recordFailedRun(for: task)

    #expect(failedTask.status == .ready)
}

@Test func reviewDoneAndArchivedTasksCannotMoveBackToReady() throws {
    for status in [TaskStatus.review, .done, .archived] {
        #expect(throws: TaskLifecycleError.transitionNotAllowed) {
            try TaskLifecyclePolicy.moveToReady(task(status: status))
        }
    }
}

@Test func reviewDoneAndArchivedTasksAreImmutable() throws {
    for status in [TaskStatus.review, .done, .archived] {
        #expect(throws: TaskLifecycleError.taskIsImmutable) {
            try TaskLifecyclePolicy.ensureEditable(task(status: status))
        }
    }
}

private func readyTask() -> OperatorTask {
    task(status: .ready)
}

private func task(status: TaskStatus) -> OperatorTask {
    var task = OperatorTask.new(
        repositoryID: UUID(),
        title: "Task",
        prompt: "Prompt"
    )
    task.status = status
    return task
}
