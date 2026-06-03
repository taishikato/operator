import { z } from "zod"

import {
  parseJsonRequest,
  schemaApplyRequiredError,
  validationError,
} from "../api/api-response.ts"
import {
  type LocalDatabaseOptions,
  resolveLocalDatabaseOptions,
} from "../db/local-database-options.ts"
import { createProjectRepository } from "./project-repository.ts"

const reasoningLevels = ["low", "medium", "high"] as const

const updateProjectSettingsRequestSchema = z
  .object({
    defaultModel: z.string().trim().min(1).max(120),
    defaultReasoningLevel: z.enum(reasoningLevels),
    scheduleEnabled: z.boolean(),
    scheduleDailyTime: z
      .string()
      .regex(/^\d{2}:\d{2}$/)
      .refine(isValidDailyTime),
    scheduleTimezone: z.string().trim().min(1).refine(isValidTimeZone),
    scheduledRunLimit: z.number().int().positive().max(100),
    runTimeoutSeconds: z.number().int().min(60).max(86_400),
  })
  .strict()

export type ProjectSettingsApiOptions = LocalDatabaseOptions & {
  projectKey: string
}

export async function resolveProjectSettingsApiOptions({
  projectKey,
}: {
  projectKey: string
}): Promise<ProjectSettingsApiOptions> {
  const databaseOptions = await resolveLocalDatabaseOptions()

  return {
    ...databaseOptions,
    projectKey,
  }
}

export async function handleUpdateProjectSettingsRequest(
  request: Request,
  options: ProjectSettingsApiOptions
) {
  if (options.databaseStatus === "requires_explicit_apply") {
    return schemaApplyRequiredError()
  }

  const body = await parseJsonRequest(request)

  if (!body.success) {
    return validationError("invalid_request", "Invalid JSON request body")
  }

  const parsed = updateProjectSettingsRequestSchema.safeParse(body.data)

  if (!parsed.success) {
    return validationError(
      "invalid_project_settings",
      "Invalid Project settings input"
    )
  }

  const projects = createProjectRepository({ databasePath: options.databasePath })
  const project = await projects.getActiveProjectByKey(options.projectKey)

  if (!project) {
    return validationError("project_not_found", "Project not found", {
      status: 404,
    })
  }

  const updatedProject = await projects.updateProjectSettings(project.id, {
    defaults: {
      model: parsed.data.defaultModel,
      reasoningLevel: parsed.data.defaultReasoningLevel,
      runTimeoutSeconds: parsed.data.runTimeoutSeconds,
    },
    schedule: {
      enabled: parsed.data.scheduleEnabled,
      dailyTime: parsed.data.scheduleDailyTime,
      timezone: parsed.data.scheduleTimezone,
      scheduledRunLimit: parsed.data.scheduledRunLimit,
    },
  })

  return Response.json({ project: updatedProject })
}

function isValidDailyTime(value: string) {
  const [hour, minute] = value.split(":").map(Number)

  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59
}

function isValidTimeZone(value: string) {
  try {
    new Intl.DateTimeFormat("en", { timeZone: value })
    return true
  } catch {
    return false
  }
}
