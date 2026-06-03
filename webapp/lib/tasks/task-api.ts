import { z } from "zod"

import { resolveAppDataPaths } from "../app-data/app-data.ts"
import { bootstrapLocalDatabase } from "../db/local-database.ts"
import { createProjectRepository } from "../projects/project-repository.ts"
import {
  canRunTaskNow,
  createRunOrchestrator,
  type CursorRunAdapter,
  type GitRunAdapter,
} from "../runs/run-orchestration.ts"
import {
  createTaskRepository,
  TaskBoardUpdateError,
  TaskValidationError,
  TASK_STATUSES,
  validateTaskStatusTransition,
  type Task,
} from "./task-repository.ts"

const createTaskRequestSchema = z.object({
  title: z.string().trim().min(1),
  bodyMarkdown: z.string(),
  acceptanceCriteriaMarkdown: z.string(),
})

const updateTaskRequestSchema = z
  .object({
    title: z.string().optional(),
    bodyMarkdown: z.string().optional(),
    acceptanceCriteriaMarkdown: z.string().optional(),
    modelOverride: z.string().nullable().optional(),
    reasoningLevelOverride: z.string().nullable().optional(),
    status: z.enum(TASK_STATUSES).optional(),
  })
  .strict()

const updateTaskBoardRequestSchema = z
  .object({
    columns: z.array(
      z
        .object({
          status: z.enum(TASK_STATUSES),
          taskDisplayIds: z.array(z.string().min(1)),
        })
        .strict()
    ),
  })
  .strict()

export type OperatorDatabaseStatus =
  | "initialized"
  | "ready"
  | "requires_explicit_apply"

export type TaskApiOptions = {
  databasePath: string
  databaseStatus: OperatorDatabaseStatus
  projectKey: string
}

export type UpdateTaskApiOptions = TaskApiOptions & {
  taskDisplayId: string
}

export type RunTaskApiOptions = UpdateTaskApiOptions & {
  cursorApiKey?: string
  cursorAdapter?: CursorRunAdapter
  gitAdapter?: GitRunAdapter
}

export async function resolveTaskApiOptions({
  projectKey,
}: {
  projectKey: string
}): Promise<TaskApiOptions> {
  const result = await bootstrapLocalDatabase(resolveAppDataPaths({}))

  return {
    databasePath: result.databasePath,
    databaseStatus: result.status,
    projectKey,
  }
}

export async function handleListTasksRequest(
  _request: Request,
  options: TaskApiOptions
) {
  if (options.databaseStatus === "requires_explicit_apply") {
    return schemaApplyRequiredError()
  }

  const project = await loadProject(options)

  if (!project) {
    return validationError("project_not_found", "Project not found", {
      status: 404,
    })
  }

  const tasks = await createTaskRepository({
    databasePath: options.databasePath,
  }).listActiveTasksForProject(project.id)

  return Response.json({ tasks })
}

export async function handleCreateTaskRequest(
  request: Request,
  options: TaskApiOptions
) {
  if (options.databaseStatus === "requires_explicit_apply") {
    return schemaApplyRequiredError()
  }

  const body = await parseJsonRequest(request)

  if (!body.success) {
    return validationError("invalid_request", "Invalid JSON request body")
  }

  const parsed = createTaskRequestSchema.safeParse(body.data)

  if (!parsed.success) {
    return validationError("invalid_request", "Invalid Task creation input")
  }

  const project = await loadProject(options)

  if (!project) {
    return validationError("project_not_found", "Project not found", {
      status: 404,
    })
  }

  const task = await createTaskRepository({
    databasePath: options.databasePath,
  }).createTask({
    projectId: project.id,
    title: parsed.data.title,
    bodyMarkdown: parsed.data.bodyMarkdown,
    acceptanceCriteriaMarkdown: parsed.data.acceptanceCriteriaMarkdown,
  })

  return Response.json({ task }, { status: 201 })
}

export async function handleUpdateTaskRequest(
  request: Request,
  options: UpdateTaskApiOptions
) {
  if (options.databaseStatus === "requires_explicit_apply") {
    return schemaApplyRequiredError()
  }

  const body = await parseJsonRequest(request)

  if (!body.success) {
    return validationError("invalid_request", "Invalid JSON request body")
  }

  const parsed = updateTaskRequestSchema.safeParse(body.data)

  if (!parsed.success) {
    return validationError("invalid_request", "Invalid Task update input")
  }

  const project = await loadProject(options)

  if (!project) {
    return validationError("project_not_found", "Project not found", {
      status: 404,
    })
  }

  const taskRepository = createTaskRepository({
    databasePath: options.databasePath,
  })
  let task = await taskRepository.getActiveTaskByDisplayId(
    options.taskDisplayId
  )

  if (!task || task.projectId !== project.id) {
    return validationError("task_not_found", "Task not found", { status: 404 })
  }

  const shouldUpdateInstructions =
    parsed.data.title !== undefined ||
    parsed.data.bodyMarkdown !== undefined ||
    parsed.data.acceptanceCriteriaMarkdown !== undefined ||
    parsed.data.modelOverride !== undefined ||
    parsed.data.reasoningLevelOverride !== undefined
  const instructionUpdate = buildTaskInstructionUpdate(task, parsed.data)

  if (parsed.data.status !== undefined) {
    try {
      validateTaskStatusTransition(
        shouldUpdateInstructions ? instructionUpdate : task,
        parsed.data.status
      )
    } catch (error) {
      if (error instanceof TaskValidationError) {
        return validationError(error.code, error.message)
      }

      throw error
    }
  }

  if (shouldUpdateInstructions) {
    task = await taskRepository.updateTaskInstructions(task.id, {
      title: instructionUpdate.title,
      bodyMarkdown: instructionUpdate.bodyMarkdown,
      acceptanceCriteriaMarkdown: instructionUpdate.acceptanceCriteriaMarkdown,
      modelOverride: instructionUpdate.modelOverride,
      reasoningLevelOverride: instructionUpdate.reasoningLevelOverride,
    })
  }

  if (parsed.data.status !== undefined) {
    task = await taskRepository.moveTaskToStatus(task.id, parsed.data.status)
  }

  return Response.json({ task })
}

export async function handleUpdateTaskBoardRequest(
  request: Request,
  options: TaskApiOptions
) {
  if (options.databaseStatus === "requires_explicit_apply") {
    return schemaApplyRequiredError()
  }

  const body = await parseJsonRequest(request)

  if (!body.success) {
    return validationError("invalid_request", "Invalid JSON request body")
  }

  const parsed = updateTaskBoardRequestSchema.safeParse(body.data)

  if (!parsed.success) {
    return validationError("invalid_request", "Invalid Task board update input")
  }

  const project = await loadProject(options)

  if (!project) {
    return validationError("project_not_found", "Project not found", {
      status: 404,
    })
  }

  let tasks: Task[]

  try {
    tasks = await createTaskRepository({
      databasePath: options.databasePath,
    }).updateTaskBoard(project.id, parsed.data.columns)
  } catch (error) {
    if (error instanceof TaskValidationError) {
      return validationError(error.code, error.message)
    }

    if (error instanceof TaskBoardUpdateError) {
      return validationError(error.code, error.message)
    }

    throw error
  }

  return Response.json({ tasks })
}

export async function handleRunTaskNowRequest(
  _request: Request,
  options: RunTaskApiOptions
) {
  if (options.databaseStatus === "requires_explicit_apply") {
    return schemaApplyRequiredError()
  }

  const project = await loadProject(options)

  if (!project) {
    return validationError("project_not_found", "Project not found", {
      status: 404,
    })
  }

  const task = await createTaskRepository({
    databasePath: options.databasePath,
  }).getActiveTaskByDisplayId(options.taskDisplayId)

  if (!task || task.projectId !== project.id) {
    return validationError("task_not_found", "Task not found", { status: 404 })
  }

  if (!canRunTaskNow(task.status)) {
    return validationError(
      "task_not_runnable",
      "Task status cannot be run now.",
      { status: 409 }
    )
  }

  const result = await createRunOrchestrator({
    databasePath: options.databasePath,
    cursorApiKey: options.cursorApiKey ?? process.env.CURSOR_API_KEY,
    cursorAdapter: options.cursorAdapter,
    gitAdapter: options.gitAdapter,
  }).runTaskNow({
    projectKey: options.projectKey,
    taskDisplayId: options.taskDisplayId,
  })

  return Response.json({ result })
}

async function loadProject(options: TaskApiOptions) {
  return createProjectRepository({
    databasePath: options.databasePath,
  }).getActiveProjectByKey(options.projectKey)
}

async function parseJsonRequest(request: Request) {
  try {
    return { success: true as const, data: await request.json() }
  } catch {
    return { success: false as const }
  }
}

function validationError(
  code: string,
  message: string,
  {
    status = 400,
  }: {
    status?: number
  } = {}
) {
  return Response.json({ error: { code, message } }, { status })
}

function schemaApplyRequiredError() {
  return validationError(
    "schema_apply_required",
    "Operator database schema is out of date. Run the explicit database apply command or reset the local Operator database.",
    { status: 503 }
  )
}

function buildTaskInstructionUpdate(
  task: Task,
  data: z.infer<typeof updateTaskRequestSchema>
): Task {
  return {
    ...task,
    title: data.title ?? task.title,
    bodyMarkdown: data.bodyMarkdown ?? task.bodyMarkdown,
    acceptanceCriteriaMarkdown:
      data.acceptanceCriteriaMarkdown ?? task.acceptanceCriteriaMarkdown,
    modelOverride:
      data.modelOverride === undefined
        ? task.modelOverride
        : normalizeNullableOverride(data.modelOverride),
    reasoningLevelOverride:
      data.reasoningLevelOverride === undefined
        ? task.reasoningLevelOverride
        : normalizeNullableOverride(data.reasoningLevelOverride),
  }
}

function normalizeNullableOverride(value: string | null) {
  if (value === null || value.trim().length === 0) {
    return null
  }

  return value
}
