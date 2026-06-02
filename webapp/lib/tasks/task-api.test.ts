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

test("handleListTasksRequest reports schema apply requirement before querying missing Task tables", async () => {
  const databasePath = await createInitializedProjectDatabaseWithoutTasks()

  const response = await handleListTasksRequest(new Request("http://test"), {
    databasePath,
    databaseStatus: "requires_explicit_apply",
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
    await client.exec(exportOperatorSchemaSql())
  } finally {
    await client.close()
  }

  return databasePath
}

async function createInitializedProjectDatabaseWithoutTasks() {
  const directory = await mkdtemp(join(tmpdir(), "operator-task-api-old-db-"))
  const databasePath = join(directory, "operator.db")
  const client = await connect(databasePath)

  try {
    await client.exec(`
CREATE TABLE operator_metadata (
  key text PRIMARY KEY,
  value text NOT NULL,
  updated_at text NOT NULL
);
INSERT INTO operator_metadata (key, value, updated_at)
VALUES ('schema_initialized', 'true', '2026-05-31T00:00:00.000Z');
CREATE TABLE projects (
  id text PRIMARY KEY,
  key text NOT NULL,
  display_name text NOT NULL,
  repo_path text NOT NULL,
  repository_name text NOT NULL,
  repository_default_branch text,
  repository_remote_url text,
  repository_github_slug text,
  repository_package_managers_json text NOT NULL,
  repository_instruction_files_json text NOT NULL,
  default_model text NOT NULL,
  default_reasoning_level text NOT NULL,
  run_timeout_seconds integer NOT NULL,
  schedule_enabled integer NOT NULL,
  schedule_daily_time text NOT NULL,
  schedule_timezone text NOT NULL,
  scheduled_run_limit integer NOT NULL,
  next_task_number integer NOT NULL,
  created_at text NOT NULL,
  updated_at text NOT NULL,
  removed_at text
);
INSERT INTO projects (
  id,
  key,
  display_name,
  repo_path,
  repository_name,
  repository_default_branch,
  repository_remote_url,
  repository_github_slug,
  repository_package_managers_json,
  repository_instruction_files_json,
  default_model,
  default_reasoning_level,
  run_timeout_seconds,
  schedule_enabled,
  schedule_daily_time,
  schedule_timezone,
  scheduled_run_limit,
  next_task_number,
  created_at,
  updated_at,
  removed_at
) VALUES (
  'project_01',
  'OP',
  'Operator',
  '/Users/example/operator',
  'operator',
  'main',
  NULL,
  NULL,
  '[]',
  '[]',
  'cursor/gpt-5',
  'high',
  3600,
  0,
  '09:00',
  'Asia/Tokyo',
  1,
  1,
  '2026-05-31T00:00:00.000Z',
  '2026-05-31T00:00:00.000Z',
  NULL
);
`)
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
