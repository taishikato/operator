import { connect } from "@tursodatabase/database"
import { drizzle } from "drizzle-orm/tursodatabase/database"
import assert from "node:assert/strict"
import { mkdtemp } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"

import { resolveAppDataPaths } from "../app-data/app-data.ts"
import { exportOperatorSchemaSql } from "../db/schema-export.ts"
import { runs } from "../db/schema.ts"
import {
  createProjectRepository,
  type CreateProjectInput,
} from "../projects/project-repository.ts"
import { createTaskRepository } from "../tasks/task-repository.ts"
import { appendRunLogEvent } from "./raw-log.ts"

test("getRunDetail returns run summary and raw log lines in file order", async () => {
  const { databasePath, appDataPaths, taskId } = await createRunDataForTest()
  const { createRunRepository } = await getRunRepository()
  const repository = createRunRepository({ databasePath, appDataPaths })

  await insertRunForTest({
    databasePath,
    id: "run_detail",
    taskId,
    taskDisplayId: "OP-1",
    status: "running",
    rawLogKey: "runs/run_detail.jsonl",
  })
  await appendRunLogEvent(appDataPaths, "runs/run_detail.jsonl", {
    source: "operator",
    type: "run.created",
    timestamp: "2026-06-01T00:00:00.000Z",
    payload: { index: 1 },
  })
  await appendRunLogEvent(appDataPaths, "runs/run_detail.jsonl", {
    source: "cursor",
    type: "cursor.stream",
    timestamp: "2026-06-01T00:00:01.000Z",
    payload: { index: 2 },
  })

  const detail = await repository.getRunDetail("run_detail")

  assert.equal(detail?.run.id, "run_detail")
  assert.equal(detail?.run.status, "running")
  assert.equal(detail?.run.rawLogKey, "runs/run_detail.jsonl")
  assert.deepEqual(
    detail?.lines.map((line) => line.type),
    ["run.created", "cursor.stream"]
  )
  assert.match(detail?.rawLogText ?? "", /run\.created/)
  assert.equal(detail?.shouldPoll, true)
})

test("shouldPollRunLog only polls active runs", async () => {
  const { shouldPollRunLog } = await getRunRepository()

  assert.equal(shouldPollRunLog("running"), true)
  assert.equal(shouldPollRunLog("review"), false)
  assert.equal(shouldPollRunLog("blocked"), false)
})

test("listLatestRunSummariesForTasks returns only the newest run for each Task", async () => {
  const { databasePath, appDataPaths, taskId } = await createRunDataForTest()
  const secondTaskId = "task_without_run"
  const { createRunRepository } = await getRunRepository()
  const repository = createRunRepository({ databasePath, appDataPaths })

  await insertRunForTest({
    databasePath,
    id: "run_old",
    taskId,
    taskDisplayId: "OP-1",
    status: "blocked",
    rawLogKey: "runs/run_old.jsonl",
    startedAt: "2026-06-01T00:00:00.000Z",
  })
  await insertRunForTest({
    databasePath,
    id: "run_new",
    taskId,
    taskDisplayId: "OP-1",
    status: "review",
    rawLogKey: "runs/run_new.jsonl",
    startedAt: "2026-06-01T00:05:00.000Z",
  })

  const summaries = await repository.listLatestRunSummariesForTasks([
    taskId,
    secondTaskId,
  ])

  assert.deepEqual(Object.keys(summaries), [taskId])
  assert.equal(summaries[taskId]?.id, "run_new")
  assert.equal(summaries[taskId]?.rawLogPath, "/runs/run_new")
})

async function getRunRepository() {
  try {
    return await import("./run-repository.ts")
  } catch {
    assert.fail("run-repository module is not implemented yet")
  }
}

async function createRunDataForTest() {
  const appDataPaths = resolveAppDataPaths({
    appDataRoot: await mkdtemp(join(tmpdir(), "operator-run-detail-")),
  })
  await initializeDatabaseForTest(appDataPaths.databasePath)
  const projects = createProjectRepository({
    databasePath: appDataPaths.databasePath,
  })
  const project = await projects.createProject(createProjectInput())
  const task = await createTaskRepository({
    databasePath: appDataPaths.databasePath,
  }).createTask({
    projectId: project.id,
    title: "Detail task",
    bodyMarkdown: "Show the raw log.",
    acceptanceCriteriaMarkdown: "- Raw log is visible",
  })

  return {
    databasePath: appDataPaths.databasePath,
    appDataPaths,
    projectId: project.id,
    taskId: task.id,
  }
}

async function initializeDatabaseForTest(databasePath: string) {
  const client = await connect(databasePath)

  try {
    await client.exec(exportOperatorSchemaSql())
  } finally {
    await client.close()
  }
}

async function insertRunForTest({
  databasePath,
  id,
  taskId,
  taskDisplayId,
  status,
  rawLogKey,
  startedAt = "2026-06-01T00:00:00.000Z",
}: {
  databasePath: string
  id: string
  taskId: string
  taskDisplayId: string
  status: "running" | "review" | "blocked"
  rawLogKey: string
  startedAt?: string
}) {
  const client = await connect(databasePath)

  try {
    const db = drizzle({ client, schema: { runs } })
    await db.insert(runs).values({
      id,
      projectId: "project_id",
      taskId,
      taskDisplayId,
      status,
      blockedReason: status === "blocked" ? "agent_error" : null,
      taskBranchName: "operator/op-1-detail-task",
      model: "cursor/gpt-5",
      reasoningLevel: "high",
      baseBranch: "main",
      headBefore: "a",
      headAfter: status === "running" ? null : "b",
      worktreeDirtyBefore: false,
      worktreeDirtyAfter: status === "running" ? null : false,
      adapterRunId: "adapter-id",
      rawLogKey,
      startedAt,
      finishedAt: status === "running" ? null : "2026-06-01T00:01:00.000Z",
      updatedAt: "2026-06-01T00:00:00.000Z",
    })
  } finally {
    await client.close()
  }
}

function createProjectInput(
  overrides: Partial<CreateProjectInput> = {}
): CreateProjectInput {
  return {
    key: "OP",
    displayName: "Operator",
    repoPath: "/Users/example/operator",
    repositoryMetadata: {
      name: "operator",
      defaultBranch: "main",
      remoteUrl: "git@github.com:example/operator.git",
      githubSlug: "example/operator",
      packageManagers: ["pnpm"],
      instructionFiles: ["AGENTS.md"],
    },
    defaults: {
      model: "cursor/gpt-5",
      reasoningLevel: "high",
      runTimeoutSeconds: 3600,
    },
    schedule: {
      enabled: false,
      dailyTime: "09:00",
      timezone: "Asia/Tokyo",
      scheduledRunLimit: 1,
    },
    ...overrides,
  }
}
