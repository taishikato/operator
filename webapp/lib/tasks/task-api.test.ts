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
import {
  handleCreateTaskRequest,
  handleListTasksRequest,
} from "./task-api.ts"

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
    { databasePath, projectKey: "OP" }
  )
  const body = await response.json()

  assert.equal(response.status, 201)
  assert.equal(body.task.displayId, "OP-1")
  assert.equal(body.task.status, "backlog")
  assert.equal(body.task.title, "Create task API")

  const listResponse = await handleListTasksRequest(new Request("http://test"), {
    databasePath,
    projectKey: "OP",
  })
  const listBody = await listResponse.json()

  assert.equal(listResponse.status, 200)
  assert.deepEqual(
    listBody.tasks.map((task: { displayId: string }) => task.displayId),
    ["OP-1"]
  )
})

async function createDatabaseForTest() {
  const directory = await mkdtemp(join(tmpdir(), "operator-task-api-"))
  const databasePath = join(directory, "operator.db")
  const client = await connect(databasePath)

  try {
    await client.exec(exportOperatorSchemaSql())
  } finally {
    await client.close()
  }

  return databasePath
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
