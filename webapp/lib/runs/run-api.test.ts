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
import { appendRunLogEvent } from "./raw-log.ts"

test("handleGetRunRequest returns run summary and raw log text", async () => {
  const { databasePath, appDataPaths } = await createRunForApiTest()
  const { handleGetRunRequest } = await getRunApi()

  const response = await handleGetRunRequest(new Request("http://test"), {
    databasePath,
    appDataPaths,
    runId: "run_api",
  })
  const body = await response.json()

  assert.equal(response.status, 200)
  assert.equal(body.run.id, "run_api")
  assert.equal(body.run.status, "running")
  assert.equal(body.shouldPoll, true)
  assert.match(body.rawLogText, /run\.created/)
})

test("handleGetRunRequest returns 404 for unknown runs", async () => {
  const appDataPaths = resolveAppDataPaths({
    appDataRoot: await mkdtemp(join(tmpdir(), "operator-run-api-")),
  })
  await initializeDatabaseForTest(appDataPaths.databasePath)
  const { handleGetRunRequest } = await getRunApi()

  const response = await handleGetRunRequest(new Request("http://test"), {
    databasePath: appDataPaths.databasePath,
    appDataPaths,
    runId: "missing",
  })
  const body = await response.json()

  assert.equal(response.status, 404)
  assert.equal(body.error.code, "run_not_found")
})

async function getRunApi() {
  try {
    return await import("./run-api.ts")
  } catch {
    assert.fail("run-api module is not implemented yet")
  }
}

async function createRunForApiTest() {
  const appDataPaths = resolveAppDataPaths({
    appDataRoot: await mkdtemp(join(tmpdir(), "operator-run-api-")),
  })
  await initializeDatabaseForTest(appDataPaths.databasePath)
  const client = await connect(appDataPaths.databasePath)

  try {
    const db = drizzle({ client, schema: { runs } })
    await db.insert(runs).values({
      id: "run_api",
      projectId: "project_id",
      taskId: "task_id",
      taskDisplayId: "OP-1",
      status: "running",
      blockedReason: null,
      taskBranchName: "operator/op-1-run-api",
      model: "cursor/gpt-5",
      reasoningLevel: "high",
      baseBranch: "main",
      headBefore: "a",
      headAfter: null,
      worktreeDirtyBefore: false,
      worktreeDirtyAfter: null,
      adapterRunId: null,
      rawLogKey: "runs/run_api.jsonl",
      startedAt: "2026-06-01T00:00:00.000Z",
      finishedAt: null,
      updatedAt: "2026-06-01T00:00:00.000Z",
    })
  } finally {
    await client.close()
  }

  await appendRunLogEvent(appDataPaths, "runs/run_api.jsonl", {
    source: "operator",
    type: "run.created",
    payload: {},
  })

  return { databasePath: appDataPaths.databasePath, appDataPaths }
}

async function initializeDatabaseForTest(databasePath: string) {
  const client = await connect(databasePath)

  try {
    await client.exec(exportOperatorSchemaSql())
  } finally {
    await client.close()
  }
}
