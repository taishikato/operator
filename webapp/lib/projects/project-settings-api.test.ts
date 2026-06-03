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
} from "./project-repository.ts"

test("handleUpdateProjectSettingsRequest persists Project defaults, schedule settings, and run timeout", async () => {
  const api = await import("./project-settings-api.ts").catch(() => null)

  assert.ok(api)

  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())
  await projects.markScheduledLocalDateFired(project.id, "2026-06-03")

  const response = await api.handleUpdateProjectSettingsRequest(
    jsonRequest({
      defaultModel: "cursor/gpt-5.1",
      defaultReasoningLevel: "medium",
      scheduleEnabled: true,
      scheduleDailyTime: "10:30",
      scheduleTimezone: "Asia/Tokyo",
      scheduledRunLimit: 4,
      runTimeoutSeconds: 1800,
    }),
    {
      databasePath,
      databaseStatus: "ready",
      projectKey: project.key,
    }
  )
  const body = await response.json()

  assert.equal(response.status, 200)
  assert.deepEqual(body.project.defaults, {
    model: "cursor/gpt-5.1",
    reasoningLevel: "medium",
    runTimeoutSeconds: 1800,
  })
  assert.deepEqual(body.project.schedule, {
    enabled: true,
    dailyTime: "10:30",
    timezone: "Asia/Tokyo",
    scheduledRunLimit: 4,
    lastScheduledLocalDate: "2026-06-03",
  })
})

test("handleUpdateProjectSettingsRequest returns validation errors without corrupting existing Project settings", async () => {
  const api = await import("./project-settings-api.ts").catch(() => null)

  assert.ok(api)

  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())

  const response = await api.handleUpdateProjectSettingsRequest(
    jsonRequest({
      defaultModel: "",
      defaultReasoningLevel: "very-high",
      scheduleEnabled: true,
      scheduleDailyTime: "25:99",
      scheduleTimezone: "",
      scheduledRunLimit: 0,
      runTimeoutSeconds: 59,
    }),
    {
      databasePath,
      databaseStatus: "ready",
      projectKey: project.key,
    }
  )
  const body = await response.json()
  const persisted = await projects.getActiveProjectByKey(project.key)

  assert.equal(response.status, 400)
  assert.deepEqual(body, {
    error: {
      code: "invalid_project_settings",
      message: "Invalid Project settings input",
    },
  })
  assert.deepEqual(persisted?.defaults, {
    model: "cursor/gpt-5",
    reasoningLevel: "high",
    runTimeoutSeconds: 3600,
  })
  assert.deepEqual(persisted?.schedule, {
    enabled: false,
    dailyTime: "09:00",
    timezone: "UTC",
    scheduledRunLimit: 1,
    lastScheduledLocalDate: null,
  })
})

async function createDatabaseForTest() {
  const directory = await mkdtemp(join(tmpdir(), "operator-settings-api-"))
  const databasePath = join(directory, "operator.db")
  const client = await connect(databasePath)

  try {
    await client.exec(exportOperatorSchemaSql())
  } finally {
    await client.close()
  }

  return databasePath
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
      timezone: "UTC",
      scheduledRunLimit: 1,
    },
    ...overrides,
  }
}

function jsonRequest(body: unknown) {
  return new Request("http://test", {
    method: "PATCH",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  })
}
