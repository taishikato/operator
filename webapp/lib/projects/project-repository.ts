import { connect } from "@tursodatabase/database"
import { and, asc, eq, isNotNull, isNull, sql } from "drizzle-orm"
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
  lastScheduledLocalDate: string | null
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
  schedule: Omit<ProjectSchedule, "lastScheduledLocalDate"> & {
    lastScheduledLocalDate?: string | null
  }
}

export type UpdateProjectScheduleInput = Omit<
  ProjectSchedule,
  "lastScheduledLocalDate"
>

export type UpdateProjectSettingsInput = {
  defaults: ProjectDefaults
  schedule: UpdateProjectScheduleInput
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

type ProjectDb = ReturnType<typeof drizzle<{ projects: typeof projects }>>

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

        const [removedRepository] = await db
          .select()
          .from(projects)
          .where(
            and(
              eq(projects.repoPath, input.repoPath),
              isNotNull(projects.removedAt)
            )
          )
          .orderBy(asc(projects.createdAt))
          .limit(1)

        if (removedRepository) {
          if (removedRepository.key !== input.key) {
            throw new ProjectRepositoryError(
              "duplicate_repository_path",
              `Removed Project repository path already exists with a different key: ${input.repoPath}`
            )
          }

          const now = new Date().toISOString()

          try {
            const [project] = await db
              .update(projects)
              .set({
                displayName: input.displayName,
                repositoryName: input.repositoryMetadata.name,
                repositoryDefaultBranch:
                  input.repositoryMetadata.defaultBranch,
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
                lastScheduledLocalDate:
                  input.schedule.lastScheduledLocalDate ?? null,
                updatedAt: now,
                removedAt: null,
              })
              .where(eq(projects.id, removedRepository.id))
              .returning()

            return toProject(project)
          } catch (error) {
            return await mapProjectConstraintError(db, input, error)
          }
        }

        const [removedProjectWithKey] = await db
          .select({ id: projects.id })
          .from(projects)
          .where(and(eq(projects.key, input.key), isNotNull(projects.removedAt)))
          .limit(1)

        if (removedProjectWithKey) {
          throw new ProjectRepositoryError(
            "duplicate_project_key",
            `Removed Project key already exists for another repository: ${input.key}`
          )
        }

        const now = new Date().toISOString()

        try {
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
              lastScheduledLocalDate:
                input.schedule.lastScheduledLocalDate ?? null,
              nextTaskNumber: 1,
              createdAt: now,
              updatedAt: now,
              removedAt: null,
            })
            .returning()

          return toProject(project)
        } catch (error) {
          return await mapProjectConstraintError(db, input, error)
        }
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

    async markScheduledLocalDateFired(
      projectId: string,
      localDate: string
    ) {
      return withDb(databasePath, async (db) => {
        const [project] = await db
          .update(projects)
          .set({
            lastScheduledLocalDate: localDate,
            updatedAt: new Date().toISOString(),
          })
          .where(and(eq(projects.id, projectId), isNull(projects.removedAt)))
          .returning()

        if (!project) {
          throw new Error(`Active Project not found: ${projectId}`)
        }

        return toProject(project)
      })
    },

    async updateScheduleSettings(
      projectId: string,
      schedule: UpdateProjectScheduleInput
    ) {
      return withDb(databasePath, async (db) => {
        const [project] = await db
          .update(projects)
          .set({
            scheduleEnabled: schedule.enabled,
            scheduleDailyTime: schedule.dailyTime,
            scheduleTimezone: schedule.timezone,
            scheduledRunLimit: schedule.scheduledRunLimit,
            updatedAt: new Date().toISOString(),
          })
          .where(and(eq(projects.id, projectId), isNull(projects.removedAt)))
          .returning()

        if (!project) {
          throw new Error(`Active Project not found: ${projectId}`)
        }

        return toProject(project)
      })
    },

    async updateProjectSettings(
      projectId: string,
      settings: UpdateProjectSettingsInput
    ) {
      return withDb(databasePath, async (db) => {
        const [project] = await db
          .update(projects)
          .set({
            defaultModel: settings.defaults.model,
            defaultReasoningLevel: settings.defaults.reasoningLevel,
            runTimeoutSeconds: settings.defaults.runTimeoutSeconds,
            scheduleEnabled: settings.schedule.enabled,
            scheduleDailyTime: settings.schedule.dailyTime,
            scheduleTimezone: settings.schedule.timezone,
            scheduledRunLimit: settings.schedule.scheduledRunLimit,
            updatedAt: new Date().toISOString(),
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
  callback: (db: ProjectDb) => Promise<T>
) {
  const client = await connect(databasePath)
  const db = drizzle({ client, schema: { projects } })

  try {
    return await callback(db)
  } finally {
    await client.close()
  }
}

async function mapProjectConstraintError(
  db: ProjectDb,
  input: CreateProjectInput,
  error: unknown
): Promise<never> {
  if (!isUniqueConstraintError(error)) {
    throw error
  }

  const text = errorText(error)

  if (text.includes("projects.key")) {
    throw new ProjectRepositoryError(
      "duplicate_project_key",
      `Active Project key already exists: ${input.key}`
    )
  }

  if (text.includes("projects.repo_path")) {
    throw new ProjectRepositoryError(
      "duplicate_repository_path",
      `Active Project repository path already exists: ${input.repoPath}`
    )
  }

  const [duplicateProject] = await db
    .select({ id: projects.id })
    .from(projects)
    .where(and(eq(projects.key, input.key), isNull(projects.removedAt)))
    .limit(1)

  if (duplicateProject) {
    throw new ProjectRepositoryError(
      "duplicate_project_key",
      `Active Project key already exists: ${input.key}`
    )
  }

  const [duplicateRepository] = await db
    .select({ id: projects.id })
    .from(projects)
    .where(
      and(eq(projects.repoPath, input.repoPath), isNull(projects.removedAt))
    )
    .limit(1)

  if (duplicateRepository) {
    throw new ProjectRepositoryError(
      "duplicate_repository_path",
      `Active Project repository path already exists: ${input.repoPath}`
    )
  }

  throw error
}

function isUniqueConstraintError(error: unknown) {
  const text = errorText(error)

  return (
    text.includes("UNIQUE constraint failed") ||
    text.includes("SQLITE_CONSTRAINT") ||
    text.includes("constraint failed")
  )
}

function errorText(error: unknown): string {
  if (error instanceof Error) {
    return `${error.message} ${errorText(error.cause)}`
  }

  return String(error ?? "")
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
      lastScheduledLocalDate: row.lastScheduledLocalDate,
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
