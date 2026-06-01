import { z } from "zod"

import { resolveAppDataPaths } from "../app-data/app-data.ts"
import { bootstrapLocalDatabase } from "../db/local-database.ts"
import { createProjectRepository } from "../projects/project-repository.ts"
import { createTaskRepository } from "./task-repository.ts"

const createTaskRequestSchema = z.object({
  title: z.string().trim().min(1),
  bodyMarkdown: z.string(),
  acceptanceCriteriaMarkdown: z.string(),
})

export type TaskApiOptions = {
  databasePath: string
  projectKey: string
}

export async function resolveTaskApiOptions({
  projectKey,
}: {
  projectKey: string
}): Promise<TaskApiOptions> {
  const result = await bootstrapLocalDatabase(resolveAppDataPaths({}))

  return { databasePath: result.databasePath, projectKey }
}

export async function handleListTasksRequest(
  _request: Request,
  options: TaskApiOptions
) {
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
