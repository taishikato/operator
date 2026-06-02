import { connect } from "@tursodatabase/database"
import assert from "node:assert/strict"
import { mkdtemp } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"

import { exportOperatorSchemaSql } from "../db/schema-export.ts"
import {
  createProjectRepository,
  type CreateProjectInput,
} from "../projects/project-repository.ts"
import { createTaskRepository } from "./task-repository.ts"

test("TaskRepository creates a Backlog Task with a stable Project display ID", async () => {
  const { projects, tasks } = await createRepositoriesForTest()
  const project = await projects.createProject(createProjectInput())

  const task = await tasks.createTask({
    projectId: project.id,
    title: "Add task persistence",
    bodyMarkdown: "Create task storage and reading behavior.",
    acceptanceCriteriaMarkdown: "- Task can be created\n- Task can be read",
  })

  assert.equal(task.projectId, project.id)
  assert.equal(task.number, 1)
  assert.equal(task.displayId, "OP-1")
  assert.equal(task.title, "Add task persistence")
  assert.equal(task.bodyMarkdown, "Create task storage and reading behavior.")
  assert.equal(
    task.acceptanceCriteriaMarkdown,
    "- Task can be created\n- Task can be read"
  )
  assert.equal(task.status, "backlog")
  assert.equal(task.position, 1)
  assert.equal(task.archivedAt, null)

  assert.deepEqual(
    (await tasks.listActiveTasksForProject(project.id)).map(
      (task) => task.displayId
    ),
    ["OP-1"]
  )
  assert.equal((await tasks.getActiveTaskByDisplayId("OP-1"))?.id, task.id)
})

test("TaskRepository does not reuse Project task numbers after archival", async () => {
  const { projects, tasks } = await createRepositoriesForTest()
  const project = await projects.createProject(createProjectInput())

  const archived = await tasks.createTask({
    projectId: project.id,
    title: "Archived task",
    bodyMarkdown: "Archive this task.",
    acceptanceCriteriaMarkdown: "- It is archived",
  })
  await tasks.archiveTask(archived.id)

  const next = await tasks.createTask({
    projectId: project.id,
    title: "Next task",
    bodyMarkdown: "Create after archive.",
    acceptanceCriteriaMarkdown: "- It uses a new number",
  })

  assert.equal(next.number, 2)
  assert.equal(next.displayId, "OP-2")
  assert.equal(await tasks.getActiveTaskByDisplayId("OP-1"), null)
  assert.deepEqual(
    (await tasks.listActiveTasksForProject(project.id)).map(
      (task) => task.displayId
    ),
    ["OP-2"]
  )
})

test("TaskRepository updates saved Task instructions explicitly", async () => {
  const { projects, tasks } = await createRepositoriesForTest()
  const project = await projects.createProject(createProjectInput())
  const task = await tasks.createTask({
    projectId: project.id,
    title: "Original title",
    bodyMarkdown: "Original body",
    acceptanceCriteriaMarkdown: "- Original criteria",
  })

  const updated = await tasks.updateTaskInstructions(task.id, {
    title: "Edited title",
    bodyMarkdown: "Edited body",
    acceptanceCriteriaMarkdown: "- Edited criteria",
    modelOverride: "cursor/gpt-5.1",
    reasoningLevelOverride: "medium",
  })

  assert.equal(updated.id, task.id)
  assert.equal(updated.title, "Edited title")
  assert.equal(updated.bodyMarkdown, "Edited body")
  assert.equal(updated.acceptanceCriteriaMarkdown, "- Edited criteria")
  assert.equal(updated.modelOverride, "cursor/gpt-5.1")
  assert.equal(updated.reasoningLevelOverride, "medium")
  assert.equal(updated.status, "backlog")

  const saved = await tasks.getActiveTaskByDisplayId("OP-1")
  assert.equal(saved?.title, "Edited title")
  assert.equal(saved?.bodyMarkdown, "Edited body")
  assert.equal(saved?.acceptanceCriteriaMarkdown, "- Edited criteria")
})

test("TaskRepository requires saved Task content before moving into Ready", async () => {
  const { projects, tasks } = await createRepositoriesForTest()
  const project = await projects.createProject(createProjectInput())
  const incomplete = await tasks.createTask({
    projectId: project.id,
    title: "  ",
    bodyMarkdown: "  ",
    acceptanceCriteriaMarkdown: "",
  })

  await assert.rejects(
    () => tasks.moveTaskToStatus(incomplete.id, "ready"),
    /Task title is required before moving to Ready/
  )

  const stillSaved = await tasks.getActiveTaskByDisplayId(incomplete.displayId)
  assert.equal(stillSaved?.title, "  ")
  assert.equal(stillSaved?.bodyMarkdown, "  ")
  assert.equal(stillSaved?.acceptanceCriteriaMarkdown, "")
  assert.equal(stillSaved?.status, "backlog")

  const withoutInstructions = await tasks.createTask({
    projectId: project.id,
    title: "Needs instructions",
    bodyMarkdown: "  ",
    acceptanceCriteriaMarkdown: "",
  })

  await assert.rejects(
    () => tasks.moveTaskToStatus(withoutInstructions.id, "ready"),
    /Task body or acceptance criteria is required before moving to Ready/
  )

  const valid = await tasks.createTask({
    projectId: project.id,
    title: "Ready task",
    bodyMarkdown: "",
    acceptanceCriteriaMarkdown: "- Has acceptance criteria",
  })

  const moved = await tasks.moveTaskToStatus(valid.id, "ready")

  assert.equal(moved.status, "ready")
  assert.equal(moved.title, "Ready task")
  assert.equal(moved.acceptanceCriteriaMarkdown, "- Has acceptance criteria")
})

test("TaskRepository exposes Ready Tasks in persisted run selection order", async () => {
  const { projects, tasks } = await createRepositoriesForTest()
  const project = await projects.createProject(createProjectInput())
  await tasks.createTask({
    projectId: project.id,
    title: "First ready task",
    bodyMarkdown: "Run this task.",
    acceptanceCriteriaMarkdown: "- It can run",
  })
  await tasks.createTask({
    projectId: project.id,
    title: "Second ready task",
    bodyMarkdown: "Run this task too.",
    acceptanceCriteriaMarkdown: "- It can run",
  })

  await tasks.updateTaskBoard(project.id, [
    { status: "ready", taskDisplayIds: ["OP-2", "OP-1"] },
  ])

  assert.deepEqual(
    (await tasks.listReadyTasksForRunSelection(project.id)).map(
      (task) => task.displayId
    ),
    ["OP-2", "OP-1"]
  )
})

test("TaskRepository rolls back board updates when a later write fails", async () => {
  const { databasePath, projects, tasks } = await createRepositoriesForTest()
  const project = await projects.createProject(createProjectInput())
  await tasks.createTask({
    projectId: project.id,
    title: "First task",
    bodyMarkdown: "Keep the original position if the board update fails.",
    acceptanceCriteriaMarkdown: "- It stays first",
  })
  await tasks.createTask({
    projectId: project.id,
    title: "Second task",
    bodyMarkdown: "This update happens before the forced failure.",
    acceptanceCriteriaMarkdown: "- It stays second after rollback",
  })
  await runSql(
    databasePath,
    `
CREATE TRIGGER fail_op_1_board_update
BEFORE UPDATE ON tasks
WHEN OLD.display_id = 'OP-1'
BEGIN
  SELECT RAISE(FAIL, 'forced board update failure');
END;
`
  )

  await assert.rejects(
    () =>
      tasks.updateTaskBoard(project.id, [
        { status: "backlog", taskDisplayIds: ["OP-2", "OP-1"] },
      ])
  )

  assert.deepEqual(
    (await tasks.listActiveTasksForProject(project.id)).map((task) => ({
      displayId: task.displayId,
      status: task.status,
      position: task.position,
    })),
    [
      { displayId: "OP-1", status: "backlog", position: 1 },
      { displayId: "OP-2", status: "backlog", position: 2 },
    ]
  )
})

async function createRepositoriesForTest() {
  const databasePath = await createDatabaseForTest()

  return {
    databasePath,
    projects: createProjectRepository({ databasePath }),
    tasks: createTaskRepository({ databasePath }),
  }
}

async function createDatabaseForTest() {
  const directory = await mkdtemp(join(tmpdir(), "operator-tasks-"))
  const databasePath = join(directory, "operator.db")
  const client = await connect(databasePath)

  try {
    await client.exec(exportOperatorSchemaSql())
  } finally {
    await client.close()
  }

  return databasePath
}

async function runSql(databasePath: string, sql: string) {
  const client = await connect(databasePath)

  try {
    await client.exec(sql)
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
