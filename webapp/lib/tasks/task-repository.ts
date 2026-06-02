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
  taskBranchName: string | null
  blockedReason: string | null
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

export type UpdateTaskInstructionsInput = {
  title: string
  bodyMarkdown: string
  acceptanceCriteriaMarkdown: string
  modelOverride: string | null
  reasoningLevelOverride: string | null
}

export type UpdateTaskBoardColumnInput = {
  status: TaskStatus
  taskDisplayIds: string[]
}

type TaskDb = ReturnType<
  typeof drizzle<{ projects: typeof projects; tasks: typeof tasks }>
>

export class TaskValidationError extends Error {
  readonly code: "ready_title_required" | "ready_content_required"

  constructor(
    code: "ready_title_required" | "ready_content_required",
    message: string
  ) {
    super(message)
    this.name = "TaskValidationError"
    this.code = code
  }
}

export class TaskBoardUpdateError extends Error {
  readonly code:
    | "running_system_controlled"
    | "duplicate_board_status"
    | "duplicate_board_task"
    | "missing_board_task"

  constructor(
    code:
      | "running_system_controlled"
      | "duplicate_board_status"
      | "duplicate_board_task"
      | "missing_board_task",
    message: string
  ) {
    super(message)
    this.name = "TaskBoardUpdateError"
    this.code = code
  }
}

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
            taskBranchName: null,
            blockedReason: null,
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

    async listReadyTasksForRunSelection(projectId: string) {
      return withDb(databasePath, async (db) => {
        const rows = await db
          .select()
          .from(tasks)
          .where(
            and(
              eq(tasks.projectId, projectId),
              eq(tasks.status, "ready"),
              isNull(tasks.archivedAt)
            )
          )
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

    async updateTaskInstructions(
      taskId: string,
      input: UpdateTaskInstructionsInput
    ) {
      return withDb(databasePath, async (db) => {
        const [task] = await db
          .update(tasks)
          .set({
            title: input.title,
            bodyMarkdown: input.bodyMarkdown,
            acceptanceCriteriaMarkdown: input.acceptanceCriteriaMarkdown,
            modelOverride: input.modelOverride,
            reasoningLevelOverride: input.reasoningLevelOverride,
            updatedAt: new Date().toISOString(),
          })
          .where(and(eq(tasks.id, taskId), isNull(tasks.archivedAt)))
          .returning()

        if (!task) {
          throw new Error(`Active Task not found: ${taskId}`)
        }

        return toTask(task)
      })
    },

    async moveTaskToStatus(taskId: string, status: TaskStatus) {
      return withDb(databasePath, async (db) => {
        const [existing] = await db
          .select()
          .from(tasks)
          .where(and(eq(tasks.id, taskId), isNull(tasks.archivedAt)))
          .limit(1)

        if (!existing) {
          throw new Error(`Active Task not found: ${taskId}`)
        }

        const currentTask = toTask(existing)
        validateTaskStatusTransition(currentTask, status)

        const position =
          currentTask.status === status
            ? currentTask.position
            : await nextPositionForStatus(db, currentTask.projectId, status)
        const [task] = await db
          .update(tasks)
          .set({
            status,
            position,
            blockedReason: status === "blocked" ? currentTask.blockedReason : null,
            updatedAt: new Date().toISOString(),
          })
          .where(and(eq(tasks.id, taskId), isNull(tasks.archivedAt)))
          .returning()

        if (!task) {
          throw new Error(`Active Task not found: ${taskId}`)
        }

        return toTask(task)
      })
    },

    async updateTaskBoard(
      projectId: string,
      columns: UpdateTaskBoardColumnInput[]
    ) {
      return withDb(databasePath, async (db) => {
        return db.transaction(async (tx) => {
          const activeRows = await tx
            .select()
            .from(tasks)
            .where(and(eq(tasks.projectId, projectId), isNull(tasks.archivedAt)))

          const tasksByDisplayId = new Map(
            activeRows.map((task) => [task.displayId, toTask(task)])
          )
          const seenStatuses = new Set<TaskStatus>()
          const seenDisplayIds = new Set<string>()
          const now = new Date().toISOString()

          for (const column of columns) {
            if (seenStatuses.has(column.status)) {
              throw new TaskBoardUpdateError(
                "duplicate_board_status",
                "Task board update cannot include the same status more than once."
              )
            }

            seenStatuses.add(column.status)

            if (column.status === "running") {
              throw new TaskBoardUpdateError(
                "running_system_controlled",
                "Running Tasks are controlled by the system and cannot be moved manually."
              )
            }

            for (const displayId of column.taskDisplayIds) {
              if (seenDisplayIds.has(displayId)) {
                throw new TaskBoardUpdateError(
                  "duplicate_board_task",
                  "Task board update cannot include the same Task more than once."
                )
              }

              seenDisplayIds.add(displayId)

              const task = tasksByDisplayId.get(displayId)

              if (!task) {
                throw new Error(`Active Task not found: ${displayId}`)
              }

              if (task.status === "running") {
                throw new TaskBoardUpdateError(
                  "running_system_controlled",
                  "Running Tasks are controlled by the system and cannot be moved manually."
                )
              }

              validateTaskStatusTransition(task, column.status)
            }
          }

          for (const task of tasksByDisplayId.values()) {
            if (task.status === "running") {
              continue
            }

            if (!seenDisplayIds.has(task.displayId)) {
              throw new TaskBoardUpdateError(
                "missing_board_task",
                "Task board update must include every active non-Running Task."
              )
            }
          }

          for (const column of columns) {
            for (const [index, displayId] of column.taskDisplayIds.entries()) {
              const task = tasksByDisplayId.get(displayId)

              if (!task) {
                throw new Error(`Active Task not found: ${displayId}`)
              }

              await tx
                .update(tasks)
                .set({
                  status: column.status,
                  position: index + 1,
                  updatedAt: now,
                })
                .where(and(eq(tasks.id, task.id), isNull(tasks.archivedAt)))
            }
          }

          return (
            await tx
              .select()
              .from(tasks)
              .where(
                and(eq(tasks.projectId, projectId), isNull(tasks.archivedAt))
              )
              .orderBy(asc(tasks.position), asc(tasks.createdAt))
          ).map(toTask)
        })
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

    async setTaskBranchName(taskId: string, branchName: string) {
      return withDb(databasePath, async (db) => {
        const [existing] = await db
          .select()
          .from(tasks)
          .where(and(eq(tasks.id, taskId), isNull(tasks.archivedAt)))
          .limit(1)

        if (!existing) {
          throw new Error(`Active Task not found: ${taskId}`)
        }

        if (existing.taskBranchName) {
          return existing.taskBranchName
        }

        const [task] = await db
          .update(tasks)
          .set({
            taskBranchName: branchName,
            updatedAt: new Date().toISOString(),
          })
          .where(and(eq(tasks.id, taskId), isNull(tasks.archivedAt)))
          .returning()

        if (!task) {
          throw new Error(`Active Task not found: ${taskId}`)
        }

        return task.taskBranchName ?? branchName
      })
    },

    async markTaskRunning(taskId: string) {
      return moveSystemControlledTaskStatus(databasePath, taskId, "running", null)
    },

    async markTaskReview(taskId: string) {
      return moveSystemControlledTaskStatus(databasePath, taskId, "review", null)
    },

    async markTaskBlocked(taskId: string, blockedReason: string) {
      return moveSystemControlledTaskStatus(
        databasePath,
        taskId,
        "blocked",
        blockedReason
      )
    },
  }
}

async function moveSystemControlledTaskStatus(
  databasePath: string,
  taskId: string,
  status: TaskStatus,
  blockedReason: string | null
) {
  return withDb(databasePath, async (db) => {
    const [existing] = await db
      .select()
      .from(tasks)
      .where(and(eq(tasks.id, taskId), isNull(tasks.archivedAt)))
      .limit(1)

    if (!existing) {
      throw new Error(`Active Task not found: ${taskId}`)
    }

    const currentTask = toTask(existing)
    const position =
      currentTask.status === status
        ? currentTask.position
        : await nextPositionForStatus(db, currentTask.projectId, status)
    const [task] = await db
      .update(tasks)
      .set({
        status,
        position,
        blockedReason,
        updatedAt: new Date().toISOString(),
      })
      .where(and(eq(tasks.id, taskId), isNull(tasks.archivedAt)))
      .returning()

    if (!task) {
      throw new Error(`Active Task not found: ${taskId}`)
    }

    return toTask(task)
  })
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

export function validateTaskStatusTransition(task: Task, status: TaskStatus) {
  if (status !== "ready") {
    return
  }

  if (task.title.trim().length === 0) {
    throw new TaskValidationError(
      "ready_title_required",
      "Task title is required before moving to Ready."
    )
  }

  if (
    task.bodyMarkdown.trim().length === 0 &&
    task.acceptanceCriteriaMarkdown.trim().length === 0
  ) {
    throw new TaskValidationError(
      "ready_content_required",
      "Task body or acceptance criteria is required before moving to Ready."
    )
  }
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
    taskBranchName: row.taskBranchName,
    blockedReason: row.blockedReason,
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
