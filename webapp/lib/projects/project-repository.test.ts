import { connect } from "@tursodatabase/database"
import assert from "node:assert/strict"
import { mkdtemp } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"

import { exportOperatorSchemaSql } from "../db/schema-export.ts"
import {
  createProjectRepository,
  ProjectRepositoryError,
  type CreateProjectInput,
} from "./project-repository.ts"

test("ProjectRepository creates and reads an active Project with repository metadata and defaults", async () => {
  const projects = await createProjectRepositoryForTest()

  const created = await projects.createProject({
    ...createProjectInput(),
  })

  const persisted = await projects.getActiveProjectByKey("OP")

  assert.equal(persisted?.id, created.id)
  assert.equal(persisted?.key, "OP")
  assert.equal(persisted?.displayName, "Operator")
  assert.equal(persisted?.repoPath, "/Users/example/operator")
  assert.deepEqual(persisted?.repositoryMetadata, {
    name: "operator",
    defaultBranch: "main",
    remoteUrl: "git@github.com:example/operator.git",
    githubSlug: "example/operator",
    packageManagers: ["pnpm"],
    instructionFiles: ["AGENTS.md"],
  })
  assert.deepEqual(persisted?.defaults, {
    model: "cursor/gpt-5",
    reasoningLevel: "high",
    runTimeoutSeconds: 3600,
  })
  assert.deepEqual(persisted?.schedule, {
    enabled: false,
    dailyTime: "09:00",
    timezone: "Asia/Tokyo",
    scheduledRunLimit: 1,
  })
  assert.equal(persisted?.nextTaskNumber, 1)
  assert.equal(persisted?.removedAt, null)
  assert.ok(Date.parse(persisted?.createdAt ?? ""))
  assert.ok(Date.parse(persisted?.updatedAt ?? ""))
})

test("ProjectRepository rejects duplicate active Project keys", async () => {
  const projects = await createProjectRepositoryForTest()
  await projects.createProject(createProjectInput())

  await assert.rejects(
    () =>
      projects.createProject(
        createProjectInput({
          repoPath: "/Users/example/other-repo",
          repositoryMetadata: {
            ...createProjectInput().repositoryMetadata,
            name: "other-repo",
          },
        })
      ),
    (error) =>
      error instanceof ProjectRepositoryError &&
      error.code === "duplicate_project_key"
  )
})

test("ProjectRepository rejects duplicate active repository paths", async () => {
  const projects = await createProjectRepositoryForTest()
  await projects.createProject(createProjectInput())

  await assert.rejects(
    () =>
      projects.createProject(
        createProjectInput({
          key: "OTHER",
          displayName: "Other",
        })
      ),
    (error) =>
      error instanceof ProjectRepositoryError &&
      error.code === "duplicate_repository_path"
  )
})

test("ProjectRepository allocates monotonically increasing Project task numbers", async () => {
  const projects = await createProjectRepositoryForTest()
  const project = await projects.createProject(createProjectInput())

  assert.equal(await projects.allocateNextTaskNumber(project.id), 1)
  assert.equal(await projects.allocateNextTaskNumber(project.id), 2)
  assert.equal(await projects.allocateNextTaskNumber(project.id), 3)

  const persisted = await projects.getActiveProjectByKey("OP")
  assert.equal(persisted?.nextTaskNumber, 4)
})

test("ProjectRepository removes Projects from active selection and scheduling without deleting history", async () => {
  const projects = await createProjectRepositoryForTest()
  const project = await projects.createProject(
    createProjectInput({
      schedule: {
        enabled: true,
        dailyTime: "09:00",
        timezone: "Asia/Tokyo",
        scheduledRunLimit: 1,
      },
    })
  )

  assert.deepEqual(
    (await projects.listActiveProjects()).map((project) => project.id),
    [project.id]
  )
  assert.deepEqual(
    (await projects.listSchedulableProjects()).map((project) => project.id),
    [project.id]
  )

  const removed = await projects.removeProject(project.id)

  assert.equal(removed.id, project.id)
  assert.ok(Date.parse(removed.removedAt ?? ""))
  assert.equal(await projects.getActiveProjectByKey("OP"), null)
  assert.deepEqual(await projects.listActiveProjects(), [])
  assert.deepEqual(await projects.listSchedulableProjects(), [])

  const historical = await projects.getProjectById(project.id)
  assert.equal(historical?.repoPath, "/Users/example/operator")
  assert.equal(historical?.removedAt, removed.removedAt)
})

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

async function createProjectRepositoryForTest() {
  const directory = await mkdtemp(join(tmpdir(), "operator-projects-"))
  const databasePath = join(directory, "operator.db")
  const client = await connect(databasePath)

  try {
    await client.exec(exportOperatorSchemaSql())
  } finally {
    await client.close()
  }

  return createProjectRepository({ databasePath })
}
