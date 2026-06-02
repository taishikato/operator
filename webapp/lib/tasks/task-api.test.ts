import { connect } from "@tursodatabase/database"
import assert from "node:assert/strict"
import { mkdir, mkdtemp } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"

import { resolveAppDataPaths } from "../app-data/app-data.ts"
import { bootstrapLocalDatabase } from "../db/local-database.ts"
import { exportOperatorSchemaSql } from "../db/schema-export.ts"
import {
  createProjectRepository,
  type CreateProjectInput,
} from "../projects/project-repository.ts"
import {
  handleCreateTaskRequest,
  handleListTasksRequest,
  handleUpdateTaskRequest,
} from "./task-api.ts"

test("handleCreateTaskRequest returns schema apply requirement when databaseStatus is requires_explicit_apply", async () => {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  await projects.createProject(createProjectInput())

  const response = await handleCreateTaskRequest(
    jsonRequest({
      title: "Blocked task",
      bodyMarkdown: "Should not persist.",
      acceptanceCriteriaMarkdown: "- Blocked",
    }),
    {
      databasePath,
      databaseStatus: "requires_explicit_apply",
      projectKey: "OP",
    }
  )
  const body = await response.json()

  assert.equal(response.status, 503)
  assert.equal(body.error.code, "schema_apply_required")
})

test("handleCreateTaskRequest creates a Project Task with display ID through the public API contract", async () => {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  await projects.createProject(createProjectInput())

  const response = await handleCreateTaskRequest(
    jsonRequest({
      title: "Create task API",
      bodyMarkdown: "Persist a task from an API request.",
      acceptanceCriteriaMarkdown: "- Response includes the display ID",
    }),
    { databasePath, databaseStatus: "ready", projectKey: "OP" }
  )
  const body = await response.json()

  assert.equal(response.status, 201)
  assert.equal(body.task.displayId, "OP-1")
  assert.equal(body.task.status, "backlog")
  assert.equal(body.task.title, "Create task API")

  const listResponse = await handleListTasksRequest(new Request("http://test"), {
    databasePath,
    databaseStatus: "ready",
    projectKey: "OP",
  })
  const listBody = await listResponse.json()

  assert.equal(listResponse.status, 200)
  assert.deepEqual(
    listBody.tasks.map((task: { displayId: string }) => task.displayId),
    ["OP-1"]
  )
})

test("handleUpdateTaskRequest saves Task instruction edits through the public API contract", async () => {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())
  const taskResponse = await handleCreateTaskRequest(
    jsonRequest({
      title: "Original title",
      bodyMarkdown: "Original body",
      acceptanceCriteriaMarkdown: "- Original criteria",
    }),
    { databasePath, databaseStatus: "ready", projectKey: project.key }
  )
  const taskBody = await taskResponse.json()

  const response = await handleUpdateTaskRequest(
    jsonRequest({
      title: "Edited title",
      bodyMarkdown: "Edited body",
      acceptanceCriteriaMarkdown: "- Edited criteria",
      modelOverride: "cursor/gpt-5.1",
      reasoningLevelOverride: "medium",
    }),
    {
      databasePath,
      databaseStatus: "ready",
      projectKey: project.key,
      taskDisplayId: taskBody.task.displayId,
    }
  )
  const body = await response.json()

  assert.equal(response.status, 200)
  assert.equal(body.task.displayId, "OP-1")
  assert.equal(body.task.title, "Edited title")
  assert.equal(body.task.bodyMarkdown, "Edited body")
  assert.equal(body.task.acceptanceCriteriaMarkdown, "- Edited criteria")
  assert.equal(body.task.modelOverride, "cursor/gpt-5.1")
  assert.equal(body.task.reasoningLevelOverride, "medium")
  assert.equal(body.task.status, "backlog")
})

test("handleUpdateTaskRequest validates only saved Task content when moving into Ready", async () => {
  const previousCursorApiKey = process.env.CURSOR_API_KEY
  delete process.env.CURSOR_API_KEY

  try {
    const databasePath = await createDatabaseForTest()
    const projects = createProjectRepository({ databasePath })
    const project = await projects.createProject(createProjectInput())
    const invalidTaskResponse = await handleCreateTaskRequest(
      jsonRequest({
        title: "No instructions",
        bodyMarkdown: "",
        acceptanceCriteriaMarkdown: "",
      }),
      { databasePath, databaseStatus: "ready", projectKey: project.key }
    )
    const invalidTaskBody = await invalidTaskResponse.json()

    const invalidResponse = await handleUpdateTaskRequest(
      jsonRequest({ status: "ready" }),
      {
        databasePath,
        databaseStatus: "ready",
        projectKey: project.key,
        taskDisplayId: invalidTaskBody.task.displayId,
      }
    )
    const invalidBody = await invalidResponse.json()

    assert.equal(invalidResponse.status, 400)
    assert.equal(invalidBody.error.code, "ready_content_required")

    const savedResponse = await handleListTasksRequest(
      new Request("http://test"),
      {
        databasePath,
        databaseStatus: "ready",
        projectKey: project.key,
      }
    )
    const savedBody = await savedResponse.json()
    assert.equal(savedBody.tasks[0].status, "backlog")
    assert.equal(savedBody.tasks[0].bodyMarkdown, "")

    const validTaskResponse = await handleCreateTaskRequest(
      jsonRequest({
        title: "Ready task",
        bodyMarkdown: "Enough saved context.",
        acceptanceCriteriaMarkdown: "",
      }),
      { databasePath, databaseStatus: "ready", projectKey: project.key }
    )
    const validTaskBody = await validTaskResponse.json()

    const readyResponse = await handleUpdateTaskRequest(
      jsonRequest({ status: "ready" }),
      {
        databasePath,
        databaseStatus: "ready",
        projectKey: project.key,
        taskDisplayId: validTaskBody.task.displayId,
      }
    )
    const readyBody = await readyResponse.json()

    assert.equal(readyResponse.status, 200)
    assert.equal(readyBody.task.status, "ready")
  } finally {
    if (previousCursorApiKey === undefined) {
      delete process.env.CURSOR_API_KEY
    } else {
      process.env.CURSOR_API_KEY = previousCursorApiKey
    }
  }
})

test("handleListTasksRequest reports schema apply requirement before querying missing Task tables", async () => {
  const directory = await mkdtemp(join(tmpdir(), "operator-task-api-old-db-"))
  const paths = resolveAppDataPaths({
    appDataRoot: join(directory, "app-data"),
  })
  await mkdir(paths.appDataDir, { recursive: true })

  const client = await connect(paths.databasePath)
  try {
    await runSql(
      client,
      `
CREATE TABLE operator_metadata (
  key text PRIMARY KEY,
  value text NOT NULL,
  updated_at text NOT NULL
);
INSERT INTO operator_metadata (key, value, updated_at)
VALUES ('schema_initialized', 'true', '2026-05-31T00:00:00.000Z');
CREATE TABLE projects (
  id text PRIMARY KEY,
  key text NOT NULL
);
INSERT INTO projects (id, key) VALUES ('project_01', 'OP');
`
    )
  } finally {
    await client.close()
  }

  const bootstrapResult = await bootstrapLocalDatabase(paths, {
    exportSchemaSql: () => {
      throw new Error("schema export should be explicit for stale databases")
    },
    applySchema: () => {
      throw new Error("schema apply should be explicit for stale databases")
    },
  })

  assert.equal(bootstrapResult.status, "requires_explicit_apply")

  const response = await handleListTasksRequest(new Request("http://test"), {
    databasePath: bootstrapResult.databasePath,
    databaseStatus: bootstrapResult.status,
    projectKey: "OP",
  })
  const body = await response.json()

  assert.equal(response.status, 503)
  assert.deepEqual(body, {
    error: {
      code: "schema_apply_required",
      message:
        "Operator database schema is out of date. Run the explicit database apply command or reset the local Operator database.",
    },
  })
})

async function createDatabaseForTest() {
  const directory = await mkdtemp(join(tmpdir(), "operator-task-api-"))
  const databasePath = join(directory, "operator.db")
  const client = await connect(databasePath)

  try {
    await runSql(client, exportOperatorSchemaSql())
  } finally {
    await client.close()
  }

  return databasePath
}

async function runSql(
  client: Awaited<ReturnType<typeof connect>>,
  sql: string
) {
  await client.exec(sql)
}

function jsonRequest(body: unknown) {
  return new Request("http://test", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  })
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
