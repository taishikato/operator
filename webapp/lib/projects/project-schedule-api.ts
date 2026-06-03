import { z } from "zod"

import {
  parseJsonRequest,
  schemaApplyRequiredError,
  validationError,
} from "../api/api-response.ts"
import { resolveAppDataPaths } from "../app-data/app-data.ts"
import { bootstrapLocalDatabase } from "../db/local-database.ts"
import { createProjectRepository } from "./project-repository.ts"

const updateProjectScheduleRequestSchema = z
  .object({
    enabled: z.boolean(),
    dailyTime: z.string().regex(/^\d{2}:\d{2}$/),
    timezone: z.string().trim().min(1),
    scheduledRunLimit: z.number().int().positive().max(100),
  })
  .strict()

export type ProjectScheduleApiOptions = {
  databasePath: string
  databaseStatus: "initialized" | "ready" | "requires_explicit_apply"
  projectKey: string
}

export async function resolveProjectScheduleApiOptions({
  projectKey,
}: {
  projectKey: string
}): Promise<ProjectScheduleApiOptions> {
  const result = await bootstrapLocalDatabase(resolveAppDataPaths({}))

  return {
    databasePath: result.databasePath,
    databaseStatus: result.status,
    projectKey,
  }
}

export async function handleUpdateProjectScheduleRequest(
  request: Request,
  options: ProjectScheduleApiOptions
) {
  if (options.databaseStatus === "requires_explicit_apply") {
    return schemaApplyRequiredError()
  }

  const body = await parseJsonRequest(request)

  if (!body.success) {
    return validationError("invalid_request", "Invalid JSON request body")
  }

  const parsed = updateProjectScheduleRequestSchema.safeParse(body.data)

  if (!parsed.success) {
    return validationError(
      "invalid_project_schedule",
      "Invalid Project schedule input"
    )
  }

  const projects = createProjectRepository({ databasePath: options.databasePath })
  const project = await projects.getActiveProjectByKey(options.projectKey)

  if (!project) {
    return validationError("project_not_found", "Project not found", {
      status: 404,
    })
  }

  const updatedProject = await projects.updateScheduleSettings(
    project.id,
    parsed.data
  )

  return Response.json({ project: updatedProject })
}
