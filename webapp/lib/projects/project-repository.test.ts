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
    lastScheduledLocalDate: null,
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

test("ProjectRepository reactivates a removed Project for the same repository without reusing task numbers", async () => {
  const projects = await createProjectRepositoryForTest()
  const project = await projects.createProject(createProjectInput())

  assert.equal(await projects.allocateNextTaskNumber(project.id), 1)
  assert.equal(await projects.allocateNextTaskNumber(project.id), 2)
  await projects.removeProject(project.id)

  const reactivated = await projects.createProject(
    createProjectInput({
      displayName: "Operator Restored",
      repositoryMetadata: {
        name: "operator",
        defaultBranch: "develop",
        remoteUrl: "git@github.com:example/operator.git",
        githubSlug: "example/operator",
        packageManagers: ["pnpm", "npm"],
        instructionFiles: ["AGENTS.md", "CLAUDE.md"],
      },
      defaults: {
        model: "cursor/gpt-5.1",
        reasoningLevel: "medium",
        runTimeoutSeconds: 1800,
      },
      schedule: {
        enabled: true,
        dailyTime: "10:30",
        timezone: "Asia/Tokyo",
        scheduledRunLimit: 2,
      },
    })
  )

  assert.equal(reactivated.id, project.id)
  assert.equal(reactivated.createdAt, project.createdAt)
  assert.equal(reactivated.removedAt, null)
  assert.equal(reactivated.nextTaskNumber, 3)
  assert.equal(reactivated.displayName, "Operator Restored")
  assert.deepEqual(reactivated.repositoryMetadata.packageManagers, [
    "pnpm",
    "npm",
  ])
  assert.deepEqual(reactivated.schedule, {
    enabled: true,
    dailyTime: "10:30",
    timezone: "Asia/Tokyo",
    scheduledRunLimit: 2,
    lastScheduledLocalDate: null,
  })
  assert.equal(await projects.allocateNextTaskNumber(project.id), 3)
})

test("ProjectRepository rejects readding a removed repository with a different Project key", async () => {
  const projects = await createProjectRepositoryForTest()
  const project = await projects.createProject(createProjectInput())
  await projects.removeProject(project.id)

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

test("ProjectRepository rejects reusing a removed Project key for a different repository", async () => {
  const projects = await createProjectRepositoryForTest()
  const project = await projects.createProject(createProjectInput())
  await projects.removeProject(project.id)

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

test("ProjectRepository maps insert-time Project key constraint violations to typed duplicate errors", async () => {
  const databasePath = await createProjectDatabaseForTest()
  await createProjectInsertRaceTrigger({
    databasePath,
    triggerName: "projects_insert_key_race",
    insertedId: "01racekey0000000000000000",
    insertedKey: "OP",
    insertedRepoPath: "/Users/example/race-winner",
    when: "NEW.key = 'OP' AND NEW.id <> '01racekey0000000000000000'",
  })
  const projects = createProjectRepository({ databasePath })

  await assert.rejects(
    () => projects.createProject(createProjectInput()),
    (error) =>
      error instanceof ProjectRepositoryError &&
      error.code === "duplicate_project_key"
  )
})

test("ProjectRepository maps insert-time repository path constraint violations to typed duplicate errors", async () => {
  const databasePath = await createProjectDatabaseForTest()
  await createProjectInsertRaceTrigger({
    databasePath,
    triggerName: "projects_insert_repo_path_race",
    insertedId: "01racerepo000000000000000",
    insertedKey: "OTHER",
    insertedRepoPath: "/Users/example/operator",
    when: "NEW.repo_path = '/Users/example/operator' AND NEW.id <> '01racerepo000000000000000'",
  })
  const projects = createProjectRepository({ databasePath })

  await assert.rejects(
    () => projects.createProject(createProjectInput()),
    (error) =>
      error instanceof ProjectRepositoryError &&
      error.code === "duplicate_repository_path"
  )
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

test("ProjectRepository records the last scheduled Project-local date that fired", async () => {
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

  const updated = await projects.markScheduledLocalDateFired(
    project.id,
    "2026-06-03"
  )

  assert.equal(updated.schedule.lastScheduledLocalDate, "2026-06-03")
  assert.equal(
    (await projects.getActiveProjectByKey("OP"))?.schedule
      .lastScheduledLocalDate,
    "2026-06-03"
  )
})

test("ProjectRepository updates Project schedule settings without clearing the last fired local date", async () => {
  const projects = await createProjectRepositoryForTest()
  const project = await projects.createProject(createProjectInput())
  await projects.markScheduledLocalDateFired(project.id, "2026-06-03")

  const updated = await projects.updateScheduleSettings(project.id, {
    enabled: true,
    dailyTime: "10:30",
    timezone: "America/New_York",
    scheduledRunLimit: 4,
  })

  assert.deepEqual(updated.schedule, {
    enabled: true,
    dailyTime: "10:30",
    timezone: "America/New_York",
    scheduledRunLimit: 4,
    lastScheduledLocalDate: "2026-06-03",
  })
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
  const databasePath = await createProjectDatabaseForTest()

  return createProjectRepository({ databasePath })
}

async function createProjectDatabaseForTest() {
  const directory = await mkdtemp(join(tmpdir(), "operator-projects-"))
  const databasePath = join(directory, "operator.db")
  const client = await connect(databasePath)

  try {
    await client.exec(exportOperatorSchemaSql())
  } finally {
    await client.close()
  }

  return databasePath
}

async function createProjectInsertRaceTrigger({
  databasePath,
  triggerName,
  insertedId,
  insertedKey,
  insertedRepoPath,
  when,
}: {
  databasePath: string
  triggerName: string
  insertedId: string
  insertedKey: string
  insertedRepoPath: string
  when: string
}) {
  const client = await connect(databasePath)

  try {
    await client.exec(`
      CREATE TRIGGER ${triggerName}
      BEFORE INSERT ON projects
      WHEN ${when}
      BEGIN
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
        )
        VALUES (
          '${insertedId}',
          '${insertedKey}',
          'Race Winner',
          '${insertedRepoPath}',
          'race-winner',
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
          '2026-01-01T00:00:00.000Z',
          '2026-01-01T00:00:00.000Z',
          NULL
        );
      END;
    `)
  } finally {
    await client.close()
  }
}
