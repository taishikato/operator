import { connect } from "@tursodatabase/database"
import assert from "node:assert/strict"
import { execFile } from "node:child_process"
import { mkdir, mkdtemp, realpath, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"
import { promisify } from "node:util"

import { exportOperatorSchemaSql } from "../db/schema-export.ts"
import { createProjectRepository } from "./project-repository.ts"
import {
  handleCreateProjectRequest,
  handleDetectProjectRequest,
} from "./add-project-api.ts"

const execFileAsync = promisify(execFile)

test("detect Project API returns repository metadata and a suggested key without creating a Project", async () => {
  const databasePath = await createProjectDatabaseForTest()
  const repoPath = await createGitRepositoryForTest("operator-api-repo-")
  await mkdir(join(repoPath, "src"))
  await writeFile(join(repoPath, "package.json"), "{}\n")

  const response = await handleDetectProjectRequest(
    jsonRequest({ repoPath: join(repoPath, "src") }),
    { databasePath }
  )
  const body = await response.json()
  const repositoryRoot = await realpath(repoPath)

  assert.equal(response.status, 200)
  assert.deepEqual(body, {
    repository: {
      path: repositoryRoot,
      name: repositoryRoot.split("/").at(-1),
      defaultBranch: "main",
      remoteUrl: null,
      githubSlug: null,
      packageManagers: ["npm"],
      instructionFiles: [],
    },
    suggestedKey: "OPERAT",
  })

  const projects = createProjectRepository({ databasePath })
  assert.deepEqual(await projects.listActiveProjects(), [])
})

test("create Project API persists a Project from a valid repository path and key", async () => {
  const databasePath = await createProjectDatabaseForTest()
  const repoPath = await createGitRepositoryForTest("operator-create-repo-")
  const repositoryRoot = await realpath(repoPath)

  const response = await handleCreateProjectRequest(
    jsonRequest({
      repoPath,
      key: "OP",
      displayName: "Operator",
    }),
    { databasePath }
  )
  const body = await response.json()

  assert.equal(response.status, 201)
  assert.equal(body.project.key, "OP")
  assert.equal(body.project.displayName, "Operator")
  assert.equal(body.project.repoPath, repositoryRoot)
  assert.deepEqual(body.project.repositoryMetadata, {
    name: repositoryRoot.split("/").at(-1),
    defaultBranch: "main",
    remoteUrl: null,
    githubSlug: null,
    packageManagers: [],
    instructionFiles: [],
  })
  assert.deepEqual(body.project.defaults, {
    model: "cursor/gpt-5",
    reasoningLevel: "high",
    runTimeoutSeconds: 3600,
  })
  assert.deepEqual(body.project.schedule, {
    enabled: false,
    dailyTime: "09:00",
    timezone: "UTC",
    scheduledRunLimit: 1,
  })
  assert.equal(body.route.projectPath, "/projects/OP")

  const projects = createProjectRepository({ databasePath })
  assert.equal((await projects.listActiveProjects()).length, 1)
})

test("create Project API returns a structured validation error for a non-Git path", async () => {
  const databasePath = await createProjectDatabaseForTest()
  const repoPath = await mkdtemp(join(tmpdir(), "operator-not-a-repo-"))

  const response = await handleCreateProjectRequest(
    jsonRequest({
      repoPath,
      key: "OP",
      displayName: "Operator",
    }),
    { databasePath }
  )
  const body = await response.json()

  assert.equal(response.status, 400)
  assert.deepEqual(body, {
    error: {
      code: "not_git_repository",
      message: "Path is not a Git repository",
      issues: [
        {
          path: ["repoPath"],
          code: "not_git_repository",
          message: "Path is not a Git repository",
        },
      ],
    },
  })
})

test("create Project API returns a structured validation error for an invalid Project key", async () => {
  const databasePath = await createProjectDatabaseForTest()
  const repoPath = await createGitRepositoryForTest(
    "operator-invalid-key-repo-"
  )

  const response = await handleCreateProjectRequest(
    jsonRequest({
      repoPath,
      key: "bad key",
      displayName: "Operator",
    }),
    { databasePath }
  )
  const body = await response.json()

  assert.equal(response.status, 400)
  assert.deepEqual(body, {
    error: {
      code: "invalid_project_key",
      message: "Project key must be 1-6 uppercase letters or numbers.",
      issues: [
        {
          path: ["key"],
          code: "invalid_project_key",
          message: "Project key must be 1-6 uppercase letters or numbers.",
        },
      ],
    },
  })

  const projects = createProjectRepository({ databasePath })
  assert.deepEqual(await projects.listActiveProjects(), [])
})

test("create Project API returns a structured validation error for a duplicate active Project key", async () => {
  const databasePath = await createProjectDatabaseForTest()
  const firstRepoPath = await createGitRepositoryForTest("operator-first-repo-")
  const secondRepoPath = await createGitRepositoryForTest(
    "operator-second-repo-"
  )

  await handleCreateProjectRequest(
    jsonRequest({
      repoPath: firstRepoPath,
      key: "OP",
      displayName: "Operator",
    }),
    { databasePath }
  )

  const response = await handleCreateProjectRequest(
    jsonRequest({
      repoPath: secondRepoPath,
      key: "OP",
      displayName: "Other",
    }),
    { databasePath }
  )
  const body = await response.json()

  assert.equal(response.status, 409)
  assert.deepEqual(body, {
    error: {
      code: "duplicate_project_key",
      message: "Active Project key already exists: OP",
      issues: [
        {
          path: ["key"],
          code: "duplicate_project_key",
          message: "Active Project key already exists: OP",
        },
      ],
    },
  })
})

test("create Project API returns a structured validation error for a duplicate active repository path", async () => {
  const databasePath = await createProjectDatabaseForTest()
  const repoPath = await createGitRepositoryForTest("operator-duplicate-repo-")

  await handleCreateProjectRequest(
    jsonRequest({
      repoPath,
      key: "OP",
      displayName: "Operator",
    }),
    { databasePath }
  )

  const response = await handleCreateProjectRequest(
    jsonRequest({
      repoPath,
      key: "OTHER",
      displayName: "Other",
    }),
    { databasePath }
  )
  const body = await response.json()
  const repositoryRoot = await realpath(repoPath)

  assert.equal(response.status, 409)
  assert.deepEqual(body, {
    error: {
      code: "duplicate_repository_path",
      message: `Active Project repository path already exists: ${repositoryRoot}`,
      issues: [
        {
          path: ["repoPath"],
          code: "duplicate_repository_path",
          message: `Active Project repository path already exists: ${repositoryRoot}`,
        },
      ],
    },
  })
})

test("create Project API does not require Cursor credentials", async () => {
  const databasePath = await createProjectDatabaseForTest()
  const repoPath = await createGitRepositoryForTest("operator-no-cursor-repo-")
  const previousCursorApiKey = process.env.CURSOR_API_KEY
  delete process.env.CURSOR_API_KEY

  try {
    const response = await handleCreateProjectRequest(
      jsonRequest({
        repoPath,
        key: "OP",
        displayName: "Operator",
      }),
      { databasePath }
    )

    assert.equal(response.status, 201)
  } finally {
    if (previousCursorApiKey === undefined) {
      delete process.env.CURSOR_API_KEY
    } else {
      process.env.CURSOR_API_KEY = previousCursorApiKey
    }
  }
})

test("detect and create Project APIs do not write files inside the managed repository", async () => {
  const databasePath = await createProjectDatabaseForTest()
  const repoPath = await createGitRepositoryForTest("operator-clean-repo-")
  const beforeStatus = await gitStatus(repoPath)

  await handleDetectProjectRequest(jsonRequest({ repoPath }), { databasePath })
  await handleCreateProjectRequest(
    jsonRequest({
      repoPath,
      key: "OP",
      displayName: "Operator",
    }),
    { databasePath }
  )

  assert.equal(beforeStatus, "")
  assert.equal(await gitStatus(repoPath), "")
})

test("Project API route handlers expose POST endpoints", async () => {
  const detectRoute = await import("../../app/api/projects/detect/route.ts")
  const projectsRoute = await import("../../app/api/projects/route.ts")

  assert.equal(typeof detectRoute.POST, "function")
  assert.equal(typeof projectsRoute.POST, "function")
})

function jsonRequest(body: unknown) {
  return new Request("http://127.0.0.1:3927/api/projects/detect", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  })
}

async function createGitRepositoryForTest(prefix: string) {
  const repoPath = await mkdtemp(join(tmpdir(), prefix))

  await execFileAsync("git", ["init", "-b", "main"], { cwd: repoPath })

  return repoPath
}

async function gitStatus(repoPath: string) {
  const { stdout } = await execFileAsync(
    "git",
    ["status", "--porcelain", "--untracked-files=all"],
    { cwd: repoPath }
  )

  return stdout.trim()
}

async function createProjectDatabaseForTest() {
  const directory = await mkdtemp(join(tmpdir(), "operator-project-api-db-"))
  const databasePath = join(directory, "operator.db")
  const client = await connect(databasePath)

  try {
    await client.exec(await exportOperatorSchemaSql())
  } finally {
    await client.close()
  }

  return databasePath
}
