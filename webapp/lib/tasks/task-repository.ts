import { connect } from "@tursodatabase/database"
import { and, asc, eq, isNull, sql } from "drizzle-orm"
import { drizzle } from "drizzle-orm/tursodatabase/database"
import { ulid } from "ulid"

import { projects, tasks } from "../db/schema.ts"

export const TASK_STATUSES = [
  "backlog",
  "ready",
  "running",
  "review",
  "done",
  "blocked",
] as const

export type TaskStatus = (typeof TASK_STATUSES)[number]

export type Task = {
  id: string
  projectId: string
  number: number
  displayId: string
  title: string
  bodyMarkdown: string
  acceptanceCriteriaMarkdown: string
  status: TaskStatus
  position: number
  modelOverride: string | null
  reasoningLevelOverride: string | null
  createdAt: string
  updatedAt: string
  archivedAt: string | null
}

export type CreateTaskInput = {
  projectId: string
  title: string
  bodyMarkdown: string
  acceptanceCriteriaMarkdown: string
}

type TaskDb = ReturnType<
  typeof drizzle<{ projects: typeof projects; tasks: typeof tasks }>
>

export function createTaskRepository({
  databasePath,
}: {
  databasePath: string
}) {
  return {
    async createTask(input: CreateTaskInput) {
      return withDb(databasePath, async (db) => {
        const [project] = await db
          .update(projects)
          .set({
            nextTaskNumber: sql`${projects.nextTaskNumber} + 1`,
            updatedAt: new Date().toISOString(),
          })
          .where(and(eq(projects.id, input.projectId), isNull(projects.removedAt)))
          .returning({
            key: projects.key,
            nextTaskNumber: projects.nextTaskNumber,
          })

        if (!project) {
          throw new Error(`Active Project not found: ${input.projectId}`)
        }

        const number = project.nextTaskNumber - 1
        const status: TaskStatus = "backlog"
        const position = await nextPositionForStatus(db, input.projectId, status)
        const now = new Date().toISOString()
        const [task] = await db
          .insert(tasks)
          .values({
            id: ulid(),
            projectId: input.projectId,
            number,
            displayId: `${project.key}-${number}`,
            title: input.title,
            bodyMarkdown: input.bodyMarkdown,
            acceptanceCriteriaMarkdown: input.acceptanceCriteriaMarkdown,
            status,
            position,
            modelOverride: null,
            reasoningLevelOverride: null,
            createdAt: now,
            updatedAt: now,
            archivedAt: null,
          })
          .returning()

        return toTask(task)
      })
    },

    async listActiveTasksForProject(projectId: string) {
      return withDb(databasePath, async (db) => {
        const rows = await db
          .select()
          .from(tasks)
          .where(and(eq(tasks.projectId, projectId), isNull(tasks.archivedAt)))
          .orderBy(asc(tasks.position), asc(tasks.createdAt))

        return rows.map(toTask)
      })
    },

    async getActiveTaskByDisplayId(displayId: string) {
      return withDb(databasePath, async (db) => {
        const [task] = await db
          .select()
          .from(tasks)
          .where(and(eq(tasks.displayId, displayId), isNull(tasks.archivedAt)))
          .limit(1)

        return task ? toTask(task) : null
      })
    },

    async archiveTask(taskId: string) {
      return withDb(databasePath, async (db) => {
        const now = new Date().toISOString()
        const [task] = await db
          .update(tasks)
          .set({
            updatedAt: now,
            archivedAt: now,
          })
          .where(and(eq(tasks.id, taskId), isNull(tasks.archivedAt)))
          .returning()

        if (!task) {
          throw new Error(`Active Task not found: ${taskId}`)
        }

        return toTask(task)
      })
    },
  }
}

async function nextPositionForStatus(
  db: TaskDb,
  projectId: string,
  status: TaskStatus
) {
  const [row] = await db
    .select({
      position: sql<number>`coalesce(max(${tasks.position}), 0)`,
    })
    .from(tasks)
    .where(
      and(
        eq(tasks.projectId, projectId),
        eq(tasks.status, status),
        isNull(tasks.archivedAt)
      )
    )

  return (row?.position ?? 0) + 1
}

async function withDb<T>(
  databasePath: string,
  callback: (db: TaskDb) => Promise<T>
) {
  const client = await connect(databasePath)
  const db = drizzle({ client, schema: { projects, tasks } })

  try {
    return await callback(db)
  } finally {
    await client.close()
  }
}

function toTask(row: typeof tasks.$inferSelect): Task {
  if (!isTaskStatus(row.status)) {
    throw new Error(`Stored Task status is invalid: ${row.status}`)
  }

  return {
    id: row.id,
    projectId: row.projectId,
    number: row.number,
    displayId: row.displayId,
    title: row.title,
    bodyMarkdown: row.bodyMarkdown,
    acceptanceCriteriaMarkdown: row.acceptanceCriteriaMarkdown,
    status: row.status,
    position: row.position,
    modelOverride: row.modelOverride,
    reasoningLevelOverride: row.reasoningLevelOverride,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    archivedAt: row.archivedAt,
  }
}

function isTaskStatus(value: string): value is TaskStatus {
  return TASK_STATUSES.includes(value as TaskStatus)
}
