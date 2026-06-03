import { z } from "zod"

import {
  parseJsonRequest,
  schemaApplyRequiredError,
  validationError,
} from "../api/api-response.ts"
import { resolveAppDataPaths } from "../app-data/app-data.ts"
import { bootstrapLocalDatabase } from "../db/local-database.ts"
import { createProjectRepository } from "../projects/project-repository.ts"
import {
  canRunTaskNow,
  createRunOrchestrator,
  ensureStaleRunsReconciled,
  type CursorRunAdapter,
  type GitRunAdapter,
} from "../runs/run-orchestration.ts"
import {
  createProjectBatchRunner,
  type ProjectBatchResult,
} from "../scheduler/project-batch-runner.ts"
import { runWithProjectExecutionLock } from "../scheduler/project-execution-lock.ts"
import {
  createTaskRepository,
  TaskBoardUpdateError,
  TaskValidationError,
  TASK_STATUSES,
  validateTaskStatusTransition,
  type Task,
} from "./task-repository.ts"
import {
  canCreateTaskPullRequest,
  createTaskPullRequest,
  createLocalTaskPrCommandAdapter,
  prepareTaskPullRequestDraft,
  type TaskPrCommandAdapter,
} from "./task-pr-creation.ts"

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

const runReadyTasksRequestSchema = z
  .object({
    count: z.number().int().positive().max(100).optional(),
  })
  .strict()

const createTaskPullRequestRequestSchema = z
  .object({
    title: z.string().trim().min(1),
    body: z.string(),
    draft: z.literal(true),
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

export type TaskPullRequestApiOptions = UpdateTaskApiOptions & {
  commandAdapter?: TaskPrCommandAdapter
}

export type RunReadyTasksApiOptions = TaskApiOptions & {
  cursorApiKey?: string
  cursorAdapter?: CursorRunAdapter
  gitAdapter?: GitRunAdapter
  batchRunner?: {
    runReadyTaskBatch(input: {
      projectId: string
      projectKey: string
      limit: number
    }): Promise<ProjectBatchResult>
  }
}

export async function resolveTaskApiOptions({
  projectKey,
}: {
  projectKey: string
}): Promise<TaskApiOptions> {
  const result = await bootstrapLocalDatabase(resolveAppDataPaths({}))

  if (result.status !== "requires_explicit_apply") {
    await ensureStaleRunsReconciled(result.databasePath)
  }

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

  const taskRepository = createTaskRepository({
    databasePath: options.databasePath,
  })
  const task = await taskRepository.getActiveTaskByDisplayId(
    options.taskDisplayId
  )

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

  if (await taskRepository.hasRunningTaskForProject(project.id)) {
    return projectTaskAlreadyRunningError()
  }

  const lockedResult = await runWithProjectExecutionLock(project.id, async () =>
    createRunOrchestrator({
      databasePath: options.databasePath,
      cursorApiKey: options.cursorApiKey ?? process.env.CURSOR_API_KEY,
      cursorAdapter: options.cursorAdapter,
      gitAdapter: options.gitAdapter,
    }).runTaskNow({
      projectKey: options.projectKey,
      taskDisplayId: options.taskDisplayId,
    })
  )

  if (lockedResult.status === "already_running") {
    return projectTaskAlreadyRunningError()
  }

  const result = lockedResult.value

  if (result.blockedReason === "task_not_runnable" && result.runId === null) {
    return validationError(
      "task_not_runnable",
      "Task status cannot be run now.",
      { status: 409 }
    )
  }

  return Response.json({ result })
}

export async function handlePrepareTaskPullRequestRequest(
  _request: Request,
  options: TaskPullRequestApiOptions
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

  const taskRepository = createTaskRepository({
    databasePath: options.databasePath,
  })
  const task = await taskRepository.getActiveTaskByDisplayId(
    options.taskDisplayId
  )

  if (!task || task.projectId !== project.id) {
    return validationError("task_not_found", "Task not found", { status: 404 })
  }

  if (!canCreateTaskPullRequest(task)) {
    return taskPullRequestUnavailableError()
  }

  const draft = await prepareTaskPullRequestDraft({
    command: options.commandAdapter ?? createLocalTaskPrCommandAdapter(),
    project,
    task,
  })

  return Response.json({ draft })
}

export async function handleCreateTaskPullRequestRequest(
  request: Request,
  options: TaskPullRequestApiOptions
) {
  if (options.databaseStatus === "requires_explicit_apply") {
    return schemaApplyRequiredError()
  }

  const body = await parseJsonRequest(request)

  if (!body.success) {
    return validationError("invalid_request", "Invalid JSON request body")
  }

  const parsed = createTaskPullRequestRequestSchema.safeParse(body.data)

  if (!parsed.success) {
    return validationError("invalid_request", "Invalid Task pull request input")
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
  const task = await taskRepository.getActiveTaskByDisplayId(
    options.taskDisplayId
  )

  if (!task || task.projectId !== project.id) {
    return validationError("task_not_found", "Task not found", { status: 404 })
  }

  if (!canCreateTaskPullRequest(task)) {
    return taskPullRequestUnavailableError()
  }

  let result: Awaited<ReturnType<typeof createTaskPullRequest>>

  try {
    result = await createTaskPullRequest({
      command: options.commandAdapter ?? createLocalTaskPrCommandAdapter(),
      project,
      task,
      confirmation: parsed.data,
    })
  } catch (error) {
    const message = pullRequestErrorMessage(error)
    await taskRepository.recordTaskPullRequestError(task.id, message)
    return validationError("pull_request_creation_failed", message, {
      status: 502,
    })
  }

  const updatedTask = await taskRepository.recordTaskPullRequestCreated(
    task.id,
    result.pullRequestUrl
  )

  return Response.json({ task: updatedTask })
}

export async function handleRunReadyTasksRequest(
  request: Request,
  options: RunReadyTasksApiOptions
) {
  if (options.databaseStatus === "requires_explicit_apply") {
    return schemaApplyRequiredError()
  }

  const body = await parseJsonRequest(request)

  if (!body.success) {
    return validationError("invalid_request", "Invalid JSON request body")
  }

  const parsed = runReadyTasksRequestSchema.safeParse(body.data)

  if (!parsed.success) {
    return validationError("invalid_request", "Invalid Ready batch input")
  }

  const project = await loadProject(options)

  if (!project) {
    return validationError("project_not_found", "Project not found", {
      status: 404,
    })
  }

  const batchRunner =
    options.batchRunner ??
    createProjectBatchRunner({
      tasks: createTaskRepository({ databasePath: options.databasePath }),
      runs: createRunOrchestrator({
        databasePath: options.databasePath,
        cursorApiKey: options.cursorApiKey ?? process.env.CURSOR_API_KEY,
        cursorAdapter: options.cursorAdapter,
        gitAdapter: options.gitAdapter,
      }),
    })
  const result = await batchRunner.runReadyTaskBatch({
    projectId: project.id,
    projectKey: project.key,
    limit: parsed.data.count ?? project.schedule.scheduledRunLimit,
  })

  if (result.status === "already_running") {
    return validationError(
      "project_batch_already_running",
      "A Ready batch is already running for this Project.",
      { status: 409 }
    )
  }

  return Response.json({ result })
}

async function loadProject(options: TaskApiOptions) {
  return createProjectRepository({
    databasePath: options.databasePath,
  }).getActiveProjectByKey(options.projectKey)
}

function projectTaskAlreadyRunningError() {
  return validationError(
    "project_task_already_running",
    "Another Task is already running for this Project.",
    { status: 409 }
  )
}

function taskPullRequestUnavailableError() {
  return validationError(
    "task_pr_unavailable",
    "A pull request can only be created for Review Tasks with a branch and no existing pull request.",
    { status: 409 }
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

function pullRequestErrorMessage(error: unknown) {
  return error instanceof Error && error.message.trim().length > 0
    ? error.message
    : "Pull request creation failed."
}
