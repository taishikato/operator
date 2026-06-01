import assert from "node:assert/strict"
import { test } from "node:test"

import {
  loadInitialProjectRoute,
  selectInitialProjectRoute,
} from "./project-routing.ts"
import type { Project } from "./project-repository.ts"

test("selectInitialProjectRoute returns null when there are no active Projects", () => {
  assert.equal(selectInitialProjectRoute([]), null)
})

test("selectInitialProjectRoute chooses the most recently created active Project", () => {
  assert.equal(
    selectInitialProjectRoute([
      project({ key: "OLD", createdAt: "2026-01-01T00:00:00.000Z" }),
      project({ key: "NEW", createdAt: "2026-02-01T00:00:00.000Z" }),
    ]),
    "/projects/NEW"
  )
})

test("loadInitialProjectRoute reads active Projects from the supplied source", async () => {
  const route = await loadInitialProjectRoute({
    listActiveProjects: async () => [
      project({ key: "FIRST", createdAt: "2026-01-01T00:00:00.000Z" }),
      project({ key: "LAST", createdAt: "2026-03-01T00:00:00.000Z" }),
    ],
  })

  assert.equal(route, "/projects/LAST")
})

function project(input: { key: string; createdAt: string }): Project {
  return {
    id: input.key,
    key: input.key,
    displayName: input.key,
    repoPath: `/tmp/${input.key}`,
    repositoryMetadata: {
      name: input.key,
      defaultBranch: "main",
      remoteUrl: null,
      githubSlug: null,
      packageManagers: [],
      instructionFiles: [],
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
    nextTaskNumber: 1,
    createdAt: input.createdAt,
    updatedAt: input.createdAt,
    removedAt: null,
  }
}
