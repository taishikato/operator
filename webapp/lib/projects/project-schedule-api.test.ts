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

test("handleUpdateProjectScheduleRequest persists schedule settings without clearing the last fired local date", async () => {
  const api = await import("./project-schedule-api.ts").catch(() => null)

  assert.ok(api)

  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())
  await projects.markScheduledLocalDateFired(project.id, "2026-06-03")

  const response = await api.handleUpdateProjectScheduleRequest(
    jsonRequest({
      enabled: true,
      dailyTime: "10:30",
      timezone: "Asia/Tokyo",
      scheduledRunLimit: 4,
    }),
    {
      databasePath,
      databaseStatus: "ready",
      projectKey: project.key,
    }
  )
  const body = await response.json()

  assert.equal(response.status, 200)
  assert.deepEqual(body.project.schedule, {
    enabled: true,
    dailyTime: "10:30",
    timezone: "Asia/Tokyo",
    scheduledRunLimit: 4,
    lastScheduledLocalDate: "2026-06-03",
  })
})

async function createDatabaseForTest() {
  const directory = await mkdtemp(join(tmpdir(), "operator-schedule-api-"))
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
