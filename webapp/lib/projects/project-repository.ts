import { connect } from "@tursodatabase/database"
import { and, asc, eq, isNull, sql } from "drizzle-orm"
import { drizzle } from "drizzle-orm/tursodatabase/database"
import { ulid } from "ulid"

import { projects } from "../db/schema.ts"

export type ProjectRepositoryMetadata = {
  name: string
  defaultBranch: string | null
  remoteUrl: string | null
  githubSlug: string | null
  packageManagers: string[]
  instructionFiles: string[]
}

export type ProjectDefaults = {
  model: string
  reasoningLevel: string
  runTimeoutSeconds: number
}

export type ProjectSchedule = {
  enabled: boolean
  dailyTime: string
  timezone: string
  scheduledRunLimit: number
}

export type Project = {
  id: string
  key: string
  displayName: string
  repoPath: string
  repositoryMetadata: ProjectRepositoryMetadata
  defaults: ProjectDefaults
  schedule: ProjectSchedule
  nextTaskNumber: number
  createdAt: string
  updatedAt: string
  removedAt: string | null
}

export type CreateProjectInput = {
  key: string
  displayName: string
  repoPath: string
  repositoryMetadata: ProjectRepositoryMetadata
  defaults: ProjectDefaults
  schedule: ProjectSchedule
}

export class ProjectRepositoryError extends Error {
  code: "duplicate_project_key" | "duplicate_repository_path"

  constructor(
    code: "duplicate_project_key" | "duplicate_repository_path",
    message: string
  ) {
    super(message)
    this.name = "ProjectRepositoryError"
    this.code = code
  }
}

export function createProjectRepository({
  databasePath,
}: {
  databasePath: string
}) {
  return {
    async createProject(input: CreateProjectInput) {
      return withDb(databasePath, async (db) => {
        const [existingProject] = await db
          .select({ id: projects.id })
          .from(projects)
          .where(and(eq(projects.key, input.key), isNull(projects.removedAt)))
          .limit(1)

        if (existingProject) {
          throw new ProjectRepositoryError(
            "duplicate_project_key",
            `Active Project key already exists: ${input.key}`
          )
        }

        const [existingRepository] = await db
          .select({ id: projects.id })
          .from(projects)
          .where(
            and(
              eq(projects.repoPath, input.repoPath),
              isNull(projects.removedAt)
            )
          )
          .limit(1)

        if (existingRepository) {
          throw new ProjectRepositoryError(
            "duplicate_repository_path",
            `Active Project repository path already exists: ${input.repoPath}`
          )
        }

        const now = new Date().toISOString()
        const [project] = await db
          .insert(projects)
          .values({
            id: ulid(),
            key: input.key,
            displayName: input.displayName,
            repoPath: input.repoPath,
            repositoryName: input.repositoryMetadata.name,
            repositoryDefaultBranch: input.repositoryMetadata.defaultBranch,
            repositoryRemoteUrl: input.repositoryMetadata.remoteUrl,
            repositoryGithubSlug: input.repositoryMetadata.githubSlug,
            repositoryPackageManagersJson: JSON.stringify(
              input.repositoryMetadata.packageManagers
            ),
            repositoryInstructionFilesJson: JSON.stringify(
              input.repositoryMetadata.instructionFiles
            ),
            defaultModel: input.defaults.model,
            defaultReasoningLevel: input.defaults.reasoningLevel,
            runTimeoutSeconds: input.defaults.runTimeoutSeconds,
            scheduleEnabled: input.schedule.enabled,
            scheduleDailyTime: input.schedule.dailyTime,
            scheduleTimezone: input.schedule.timezone,
            scheduledRunLimit: input.schedule.scheduledRunLimit,
            nextTaskNumber: 1,
            createdAt: now,
            updatedAt: now,
            removedAt: null,
          })
          .returning()

        return toProject(project)
      })
    },

    async getActiveProjectByKey(key: string) {
      return withDb(databasePath, async (db) => {
        const [project] = await db
          .select()
          .from(projects)
          .where(and(eq(projects.key, key), isNull(projects.removedAt)))
          .limit(1)

        return project ? toProject(project) : null
      })
    },

    async getProjectById(projectId: string) {
      return withDb(databasePath, async (db) => {
        const [project] = await db
          .select()
          .from(projects)
          .where(eq(projects.id, projectId))
          .limit(1)

        return project ? toProject(project) : null
      })
    },

    async listActiveProjects() {
      return withDb(databasePath, async (db) => {
        const rows = await db
          .select()
          .from(projects)
          .where(isNull(projects.removedAt))
          .orderBy(asc(projects.createdAt))

        return rows.map(toProject)
      })
    },

    async listSchedulableProjects() {
      return withDb(databasePath, async (db) => {
        const rows = await db
          .select()
          .from(projects)
          .where(
            and(isNull(projects.removedAt), eq(projects.scheduleEnabled, true))
          )
          .orderBy(asc(projects.createdAt))

        return rows.map(toProject)
      })
    },

    async allocateNextTaskNumber(projectId: string) {
      return withDb(databasePath, async (db) => {
        const [project] = await db
          .update(projects)
          .set({
            nextTaskNumber: sql`${projects.nextTaskNumber} + 1`,
            updatedAt: new Date().toISOString(),
          })
          .where(and(eq(projects.id, projectId), isNull(projects.removedAt)))
          .returning({ nextTaskNumber: projects.nextTaskNumber })

        if (!project) {
          throw new Error(`Active Project not found: ${projectId}`)
        }

        return project.nextTaskNumber - 1
      })
    },

    async removeProject(projectId: string) {
      return withDb(databasePath, async (db) => {
        const now = new Date().toISOString()
        const [project] = await db
          .update(projects)
          .set({
            updatedAt: now,
            removedAt: now,
          })
          .where(and(eq(projects.id, projectId), isNull(projects.removedAt)))
          .returning()

        if (!project) {
          throw new Error(`Active Project not found: ${projectId}`)
        }

        return toProject(project)
      })
    },
  }
}

async function withDb<T>(
  databasePath: string,
  callback: (
    db: ReturnType<typeof drizzle<{ projects: typeof projects }>>
  ) => Promise<T>
) {
  const client = await connect(databasePath)
  const db = drizzle({ client, schema: { projects } })

  try {
    return await callback(db)
  } finally {
    await client.close()
  }
}

function toProject(row: typeof projects.$inferSelect): Project {
  return {
    id: row.id,
    key: row.key,
    displayName: row.displayName,
    repoPath: row.repoPath,
    repositoryMetadata: {
      name: row.repositoryName,
      defaultBranch: row.repositoryDefaultBranch,
      remoteUrl: row.repositoryRemoteUrl,
      githubSlug: row.repositoryGithubSlug,
      packageManagers: parseStringArray(row.repositoryPackageManagersJson),
      instructionFiles: parseStringArray(row.repositoryInstructionFilesJson),
    },
    defaults: {
      model: row.defaultModel,
      reasoningLevel: row.defaultReasoningLevel,
      runTimeoutSeconds: row.runTimeoutSeconds,
    },
    schedule: {
      enabled: row.scheduleEnabled,
      dailyTime: row.scheduleDailyTime,
      timezone: row.scheduleTimezone,
      scheduledRunLimit: row.scheduledRunLimit,
    },
    nextTaskNumber: row.nextTaskNumber,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    removedAt: row.removedAt,
  }
}

function parseStringArray(value: string) {
  const parsed = JSON.parse(value)

  if (
    !Array.isArray(parsed) ||
    parsed.some((item) => typeof item !== "string")
  ) {
    throw new Error("Stored Project metadata is not a string array")
  }

  return parsed
}
