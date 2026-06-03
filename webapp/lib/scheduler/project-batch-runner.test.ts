import assert from "node:assert/strict"
import { test } from "node:test"

import { createProjectBatchRunner } from "./project-batch-runner.ts"

test("runReadyTaskBatch runs Ready Tasks in persisted order up to the limit", async () => {
  const calls: string[] = []
  const runner = createProjectBatchRunner({
    tasks: readyTasks("OP-3", "OP-1", "OP-2"),
    runs: {
      async runTaskNow({ taskDisplayId }) {
        calls.push(taskDisplayId)
        return reviewResult()
      },
    },
  })

  const result = await runner.runReadyTaskBatch({
    projectId: "project_01",
    projectKey: "OP",
    limit: 2,
  })

  assert.equal(result.status, "completed")
  assert.deepEqual(calls, ["OP-3", "OP-1"])
})

test("runReadyTaskBatch stops a Project batch after the first blocked result", async () => {
  const calls: string[] = []
  const runner = createProjectBatchRunner({
    tasks: readyTasks("OP-1", "OP-2", "OP-3"),
    runs: {
      async runTaskNow({ taskDisplayId }) {
        calls.push(taskDisplayId)
        return taskDisplayId === "OP-2"
          ? blockedResult("timeout")
          : reviewResult()
      },
    },
  })

  const result = await runner.runReadyTaskBatch({
    projectId: "project_01",
    projectKey: "OP",
    limit: 3,
  })

  assert.equal(result.status, "stopped")
  assert.deepEqual(calls, ["OP-1", "OP-2"])
})

test("runReadyTaskBatch prevents overlapping batches for the same Project", async () => {
  const firstRun = deferred<void>()
  const runner = createProjectBatchRunner({
    tasks: readyTasks("OP-1"),
    runs: {
      async runTaskNow() {
        await firstRun.promise
        return reviewResult()
      },
    },
  })

  const firstBatch = runner.runReadyTaskBatch({
    projectId: "project_01",
    projectKey: "OP",
    limit: 1,
  })
  const secondBatch = await runner.runReadyTaskBatch({
    projectId: "project_01",
    projectKey: "OP",
    limit: 1,
  })

  firstRun.resolve()

  assert.equal(secondBatch.status, "already_running")
  assert.equal((await firstBatch).status, "completed")
})

test("runReadyTaskBatch shares Project concurrency across runner instances", async () => {
  const firstRun = deferred<void>()
  const firstRunner = createProjectBatchRunner({
    tasks: readyTasks("OP-1"),
    runs: {
      async runTaskNow() {
        await firstRun.promise
        return reviewResult()
      },
    },
  })
  const secondRunner = createProjectBatchRunner({
    tasks: readyTasks("OP-2"),
    runs: {
      async runTaskNow() {
        return reviewResult()
      },
    },
  })

  const firstBatch = firstRunner.runReadyTaskBatch({
    projectId: "project_01",
    projectKey: "OP",
    limit: 1,
  })
  const secondBatch = await secondRunner.runReadyTaskBatch({
    projectId: "project_01",
    projectKey: "OP",
    limit: 1,
  })

  firstRun.resolve()

  assert.equal(secondBatch.status, "already_running")
  assert.equal((await firstBatch).status, "completed")
})

test("runReadyTaskBatch allows different Projects to run concurrently", async () => {
  const firstRun = deferred<void>()
  const calls: string[] = []
  const runner = createProjectBatchRunner({
    tasks: {
      async listReadyTasksForRunSelection(projectId) {
        return [{ displayId: projectId === "project_01" ? "OP-1" : "DOC-1" }]
      },
    },
    runs: {
      async runTaskNow({ taskDisplayId }) {
        calls.push(taskDisplayId)
        await firstRun.promise
        return reviewResult()
      },
    },
  })

  const firstBatch = runner.runReadyTaskBatch({
    projectId: "project_01",
    projectKey: "OP",
    limit: 1,
  })
  const secondBatch = runner.runReadyTaskBatch({
    projectId: "project_02",
    projectKey: "DOC",
    limit: 1,
  })

  await Promise.resolve()
  assert.deepEqual(calls.sort(), ["DOC-1", "OP-1"])

  firstRun.resolve()

  assert.equal((await firstBatch).status, "completed")
  assert.equal((await secondBatch).status, "completed")
})

function readyTasks(...displayIds: string[]) {
  return {
    async listReadyTasksForRunSelection() {
      return displayIds.map((displayId) => ({ displayId }))
    },
  }
}

function reviewResult() {
  return {
    status: "review" as const,
    blockedReason: null,
    taskBranchName: "operator/op-1-task",
    runId: "run_01",
  }
}

function blockedResult(blockedReason: "timeout") {
  return {
    status: "blocked" as const,
    blockedReason,
    taskBranchName: "operator/op-2-task",
    runId: "run_02",
  }
}

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void
  const promise = new Promise<T>((innerResolve) => {
    resolve = innerResolve
  })

  return { promise, resolve }
}
