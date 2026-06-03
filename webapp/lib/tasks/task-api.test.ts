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
import { createTaskRepository } from "./task-repository.ts"
import {
  handleCreateTaskRequest,
  handleListTasksRequest,
  handleRunTaskNowRequest,
  handleUpdateTaskBoardRequest,
  handleUpdateTaskRequest,
} from "./task-api.ts"
import type {
  CursorRunAdapter,
  GitRunAdapter,
} from "../runs/run-orchestration.ts"

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

  const listResponse = await handleListTasksRequest(
    new Request("http://test"),
    {
      databasePath,
      databaseStatus: "ready",
      projectKey: "OP",
    }
  )
  const listBody = await listResponse.json()

  assert.equal(listResponse.status, 200)
  assert.deepEqual(
    listBody.tasks.map((task: { displayId: string }) => task.displayId),
    ["OP-1"]
  )
})

test("handleUpdateTaskBoardRequest persists same-column ordering through the public board API", async () => {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())

  await handleCreateTaskRequest(
    jsonRequest({
      title: "First backlog task",
      bodyMarkdown: "First task body.",
      acceptanceCriteriaMarkdown: "- First task is saved",
    }),
    { databasePath, databaseStatus: "ready", projectKey: project.key }
  )
  await handleCreateTaskRequest(
    jsonRequest({
      title: "Second backlog task",
      bodyMarkdown: "Second task body.",
      acceptanceCriteriaMarkdown: "- Second task is saved",
    }),
    { databasePath, databaseStatus: "ready", projectKey: project.key }
  )

  const response = await handleUpdateTaskBoardRequest(
    jsonRequest({
      columns: [{ status: "backlog", taskDisplayIds: ["OP-2", "OP-1"] }],
    }),
    { databasePath, databaseStatus: "ready", projectKey: project.key }
  )
  const body = await response.json()

  assert.equal(response.status, 200)
  assert.deepEqual(
    body.tasks.map((task: { displayId: string; position: number }) => ({
      displayId: task.displayId,
      position: task.position,
    })),
    [
      { displayId: "OP-2", position: 1 },
      { displayId: "OP-1", position: 2 },
    ]
  )

  const listResponse = await handleListTasksRequest(
    new Request("http://test"),
    {
      databasePath,
      databaseStatus: "ready",
      projectKey: project.key,
    }
  )
  const listBody = await listResponse.json()

  assert.deepEqual(
    listBody.tasks.map((task: { displayId: string; position: number }) => ({
      displayId: task.displayId,
      position: task.position,
    })),
    [
      { displayId: "OP-2", position: 1 },
      { displayId: "OP-1", position: 2 },
    ]
  )
})

test("handleUpdateTaskBoardRequest rejects duplicate Task display IDs in the board payload", async () => {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())
  await createTaskThroughApi(databasePath, project.key, {
    title: "First task",
    bodyMarkdown: "This task can move.",
    acceptanceCriteriaMarkdown: "- It is valid",
  })

  const response = await handleUpdateTaskBoardRequest(
    jsonRequest({
      columns: [
        { status: "backlog", taskDisplayIds: ["OP-1"] },
        { status: "ready", taskDisplayIds: ["OP-1"] },
      ],
    }),
    { databasePath, databaseStatus: "ready", projectKey: project.key }
  )
  const body = await response.json()

  assert.equal(response.status, 400)
  assert.equal(body.error.code, "duplicate_board_task")
})

test("handleUpdateTaskBoardRequest rejects duplicate statuses in the board payload", async () => {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())
  await createTaskThroughApi(databasePath, project.key, {
    title: "First task",
    bodyMarkdown: "This task can move.",
    acceptanceCriteriaMarkdown: "- It is valid",
  })
  await createTaskThroughApi(databasePath, project.key, {
    title: "Second task",
    bodyMarkdown: "This task can move too.",
    acceptanceCriteriaMarkdown: "- It is valid",
  })

  const response = await handleUpdateTaskBoardRequest(
    jsonRequest({
      columns: [
        { status: "backlog", taskDisplayIds: ["OP-1"] },
        { status: "backlog", taskDisplayIds: ["OP-2"] },
      ],
    }),
    { databasePath, databaseStatus: "ready", projectKey: project.key }
  )
  const body = await response.json()

  assert.equal(response.status, 400)
  assert.equal(body.error.code, "duplicate_board_status")
})

test("handleUpdateTaskBoardRequest rejects payloads missing active non-Running Tasks", async () => {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())
  await createTaskThroughApi(databasePath, project.key, {
    title: "First task",
    bodyMarkdown: "This task can move.",
    acceptanceCriteriaMarkdown: "- It is valid",
  })
  await createTaskThroughApi(databasePath, project.key, {
    title: "Second task",
    bodyMarkdown: "This task should not disappear from the board payload.",
    acceptanceCriteriaMarkdown: "- It remains represented",
  })

  const response = await handleUpdateTaskBoardRequest(
    jsonRequest({
      columns: [{ status: "backlog", taskDisplayIds: ["OP-1"] }],
    }),
    { databasePath, databaseStatus: "ready", projectKey: project.key }
  )
  const body = await response.json()

  assert.equal(response.status, 400)
  assert.equal(body.error.code, "missing_board_task")
})

test("handleUpdateTaskBoardRequest rejects manual movement into Running", async () => {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())

  await handleCreateTaskRequest(
    jsonRequest({
      title: "Backlog task",
      bodyMarkdown: "This task should not enter Running manually.",
      acceptanceCriteriaMarkdown: "- Running stays system-controlled",
    }),
    { databasePath, databaseStatus: "ready", projectKey: project.key }
  )

  const response = await handleUpdateTaskBoardRequest(
    jsonRequest({
      columns: [{ status: "running", taskDisplayIds: ["OP-1"] }],
    }),
    { databasePath, databaseStatus: "ready", projectKey: project.key }
  )
  const body = await response.json()

  assert.equal(response.status, 400)
  assert.equal(body.error.code, "running_system_controlled")

  const listResponse = await handleListTasksRequest(
    new Request("http://test"),
    {
      databasePath,
      databaseStatus: "ready",
      projectKey: project.key,
    }
  )
  const listBody = await listResponse.json()

  assert.equal(listBody.tasks[0].status, "backlog")
  assert.equal(listBody.tasks[0].position, 1)
})

test("handleUpdateTaskBoardRequest rejects manual movement out of Running", async () => {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())
  const tasks = createTaskRepository({ databasePath })
  const task = await tasks.createTask({
    projectId: project.id,
    title: "Running task",
    bodyMarkdown: "The system owns this Task while it is running.",
    acceptanceCriteriaMarkdown: "- Running cannot be moved manually",
  })
  await tasks.moveTaskToStatus(task.id, "running")

  const response = await handleUpdateTaskBoardRequest(
    jsonRequest({
      columns: [{ status: "review", taskDisplayIds: ["OP-1"] }],
    }),
    { databasePath, databaseStatus: "ready", projectKey: project.key }
  )
  const body = await response.json()

  assert.equal(response.status, 400)
  assert.equal(body.error.code, "running_system_controlled")

  const saved = await tasks.getActiveTaskByDisplayId("OP-1")
  assert.equal(saved?.status, "running")
  assert.equal(saved?.position, 1)
})

test("handleUpdateTaskBoardRequest rejects manual Running position changes", async () => {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())
  const tasks = createTaskRepository({ databasePath })
  const first = await tasks.createTask({
    projectId: project.id,
    title: "First running task",
    bodyMarkdown: "The system owns this Task while it is running.",
    acceptanceCriteriaMarkdown: "- Running cannot be reordered manually",
  })
  await tasks.moveTaskToStatus(first.id, "running")
  const second = await tasks.createTask({
    projectId: project.id,
    title: "Second running task",
    bodyMarkdown: "The system owns this Task while it is running too.",
    acceptanceCriteriaMarkdown: "- Running cannot be reordered manually",
  })
  await tasks.moveTaskToStatus(second.id, "running")

  const response = await handleUpdateTaskBoardRequest(
    jsonRequest({
      columns: [{ status: "running", taskDisplayIds: ["OP-2", "OP-1"] }],
    }),
    { databasePath, databaseStatus: "ready", projectKey: project.key }
  )
  const body = await response.json()

  assert.equal(response.status, 400)
  assert.equal(body.error.code, "running_system_controlled")

  const saved = await tasks.listActiveTasksForProject(project.id)
  assert.deepEqual(
    saved.map((task) => ({
      displayId: task.displayId,
      status: task.status,
      position: task.position,
    })),
    [
      { displayId: "OP-1", status: "running", position: 1 },
      { displayId: "OP-2", status: "running", position: 2 },
    ]
  )
})

test("handleUpdateTaskBoardRequest reuses Ready validation for board moves", async () => {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())

  await handleCreateTaskRequest(
    jsonRequest({
      title: "No instructions yet",
      bodyMarkdown: "",
      acceptanceCriteriaMarkdown: "",
    }),
    { databasePath, databaseStatus: "ready", projectKey: project.key }
  )

  const response = await handleUpdateTaskBoardRequest(
    jsonRequest({
      columns: [{ status: "ready", taskDisplayIds: ["OP-1"] }],
    }),
    { databasePath, databaseStatus: "ready", projectKey: project.key }
  )
  const body = await response.json()

  assert.equal(response.status, 400)
  assert.equal(body.error.code, "ready_content_required")

  const listResponse = await handleListTasksRequest(
    new Request("http://test"),
    {
      databasePath,
      databaseStatus: "ready",
      projectKey: project.key,
    }
  )
  const listBody = await listResponse.json()

  assert.equal(listBody.tasks[0].status, "backlog")
  assert.equal(listBody.tasks[0].position, 1)
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

test("handleUpdateTaskRequest rejects mixed Ready moves without persisting instruction edits", async () => {
  const previousCursorApiKey = process.env.CURSOR_API_KEY
  delete process.env.CURSOR_API_KEY

  try {
    const databasePath = await createDatabaseForTest()
    const projects = createProjectRepository({ databasePath })
    const project = await projects.createProject(createProjectInput())
    const taskResponse = await handleCreateTaskRequest(
      jsonRequest({
        title: "Ready task",
        bodyMarkdown: "Enough saved context.",
        acceptanceCriteriaMarkdown: "",
      }),
      { databasePath, databaseStatus: "ready", projectKey: project.key }
    )
    const taskBody = await taskResponse.json()

    const response = await handleUpdateTaskRequest(
      jsonRequest({
        title: "",
        status: "ready",
      }),
      {
        databasePath,
        databaseStatus: "ready",
        projectKey: project.key,
        taskDisplayId: taskBody.task.displayId,
      }
    )
    const body = await response.json()

    assert.equal(response.status, 400)
    assert.equal(body.error.code, "ready_title_required")

    const savedResponse = await handleListTasksRequest(
      new Request("http://test"),
      {
        databasePath,
        databaseStatus: "ready",
        projectKey: project.key,
      }
    )
    const savedBody = await savedResponse.json()

    assert.equal(savedBody.tasks[0].title, "Ready task")
    assert.equal(savedBody.tasks[0].status, "backlog")
    assert.equal(savedBody.tasks[0].bodyMarkdown, "Enough saved context.")
  } finally {
    if (previousCursorApiKey === undefined) {
      delete process.env.CURSOR_API_KEY
    } else {
      process.env.CURSOR_API_KEY = previousCursorApiKey
    }
  }
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

test("handleRunTaskNowRequest runs a Task through fake adapters without requiring real Cursor credentials", async () => {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())
  await createTaskThroughApi(databasePath, project.key, {
    title: "Run now API",
    bodyMarkdown: "Run through the public API.",
    acceptanceCriteriaMarkdown: "- Fake Cursor adapter is called",
  })
  const cursor = new FakeCursorRunAdapter()

  const response = await handleRunTaskNowRequest(new Request("http://test"), {
    databasePath,
    databaseStatus: "ready",
    projectKey: project.key,
    taskDisplayId: "OP-1",
    cursorApiKey: "test-cursor-key",
    cursorAdapter: cursor,
    gitAdapter: new FakeGitRunAdapter(),
  })
  const body = await response.json()

  assert.equal(response.status, 200)
  assert.equal(body.result.status, "review")
  assert.equal(body.result.taskBranchName, "operator/op-1-run-now-api")
  assert.equal(cursor.calls.length, 1)
})

test("handleRunTaskNowRequest rejects a Running Task without mutating it", async () => {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())
  await createTaskThroughApi(databasePath, project.key, {
    title: "Already running",
    bodyMarkdown: "This Task is already running.",
    acceptanceCriteriaMarkdown: "- Direct Run Now is rejected",
  })
  const tasks = createTaskRepository({ databasePath })
  const task = await tasks.getActiveTaskByDisplayId("OP-1")

  assert.ok(task)
  await tasks.markTaskRunning(task.id)

  const cursor = new FakeCursorRunAdapter()
  const response = await handleRunTaskNowRequest(new Request("http://test"), {
    databasePath,
    databaseStatus: "ready",
    projectKey: project.key,
    taskDisplayId: "OP-1",
    cursorApiKey: "test-cursor-key",
    cursorAdapter: cursor,
    gitAdapter: new FakeGitRunAdapter(),
  })
  const body = await response.json()
  const saved = await tasks.getActiveTaskByDisplayId("OP-1")

  assert.equal(response.status, 409)
  assert.equal(body.error.code, "task_not_runnable")
  assert.equal(cursor.calls.length, 0)
  assert.equal(saved?.status, "running")
  assert.equal(saved?.blockedReason, null)
  assert.equal(saved?.taskBranchName, null)
})

test("handleRunTaskNowRequest rejects a Done Task without mutating it", async () => {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())
  await createTaskThroughApi(databasePath, project.key, {
    title: "Already done",
    bodyMarkdown: "This Task is complete.",
    acceptanceCriteriaMarkdown: "- Direct Run Now is rejected",
  })
  const tasks = createTaskRepository({ databasePath })
  const task = await tasks.getActiveTaskByDisplayId("OP-1")

  assert.ok(task)
  await tasks.moveTaskToStatus(task.id, "done")

  const cursor = new FakeCursorRunAdapter()
  const response = await handleRunTaskNowRequest(new Request("http://test"), {
    databasePath,
    databaseStatus: "ready",
    projectKey: project.key,
    taskDisplayId: "OP-1",
    cursorApiKey: "test-cursor-key",
    cursorAdapter: cursor,
    gitAdapter: new FakeGitRunAdapter(),
  })
  const body = await response.json()
  const saved = await tasks.getActiveTaskByDisplayId("OP-1")

  assert.equal(response.status, 409)
  assert.equal(body.error.code, "task_not_runnable")
  assert.equal(cursor.calls.length, 0)
  assert.equal(saved?.status, "done")
  assert.equal(saved?.blockedReason, null)
  assert.equal(saved?.taskBranchName, null)
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

test("Task board API route exposes a PATCH endpoint", async () => {
  const boardRoute =
    await import("../../app/api/projects/[projectKey]/tasks/board/route.ts")

  assert.equal(typeof boardRoute.PATCH, "function")
})

test("Task Run Now API route exposes a POST endpoint", async () => {
  const runRoute =
    await import("../../app/api/projects/[projectKey]/tasks/[taskDisplayId]/run/route.ts")

  assert.equal(typeof runRoute.POST, "function")
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

async function createTaskThroughApi(
  databasePath: string,
  projectKey: string,
  body: {
    title: string
    bodyMarkdown: string
    acceptanceCriteriaMarkdown: string
  }
) {
  return handleCreateTaskRequest(jsonRequest(body), {
    databasePath,
    databaseStatus: "ready",
    projectKey,
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

class FakeGitRunAdapter implements GitRunAdapter {
  private headCalls = 0

  async repositoryExists() {
    return true
  }

  async isGitRepository() {
    return true
  }

  async getCurrentBranch() {
    return "main"
  }

  async isWorktreeClean() {
    return true
  }

  async getHeadSha() {
    this.headCalls += 1
    return this.headCalls === 1 ? "before" : "after"
  }

  async checkoutOrCreateBranch() {}
}

class FakeCursorRunAdapter implements CursorRunAdapter {
  calls: Array<{ prompt: string }> = []

  async run(input: { prompt: string }) {
    this.calls.push(input)
    return { adapterRunId: "fake-run" }
  }
}
