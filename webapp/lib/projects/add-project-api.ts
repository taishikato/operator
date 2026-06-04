import { z } from "zod"

import { parseJsonRequest, validationError } from "../api/api-response.ts"
import { resolveLocalDatabaseOptions } from "../db/local-database-options.ts"
import {
  defaultCursorModel,
  defaultCursorReasoningLevel,
} from "../cursor-models.ts"
import {
  detectProjectRepository,
  ProjectRepositoryDetectionError,
} from "./detect-project-repository.ts"
import { suggestProjectKey } from "./project-key.ts"
import {
  createProjectRepository,
  ProjectRepositoryError,
} from "./project-repository.ts"

const detectProjectRequestSchema = z.object({
  repoPath: z.string().trim().min(1),
})

const PROJECT_KEY_ERROR_MESSAGE =
  "Project key must be 1-6 uppercase letters or numbers."

const createProjectRequestSchema = z.object({
  repoPath: z.string().trim().min(1),
  key: z
    .string()
    .trim()
    .regex(/^[A-Z0-9]{1,6}$/, PROJECT_KEY_ERROR_MESSAGE),
  displayName: z.string().trim().min(1),
})

type AddProjectApiOptions = {
  databasePath: string
  databaseStatus?: "initialized" | "ready" | "requires_explicit_apply"
}

export async function resolveAddProjectApiOptions(): Promise<AddProjectApiOptions> {
  return resolveLocalDatabaseOptions()
}

export async function handleDetectProjectRequest(
  request: Request,
  _options?: AddProjectApiOptions
) {
  void _options

  const body = await parseJsonRequest(request)

  if (!body.success) {
    return validationError("invalid_request", "Invalid JSON request body")
  }

  const parsed = detectProjectRequestSchema.safeParse(body.data)

  if (!parsed.success) {
    return validationError("invalid_request", "Invalid Project detection input")
  }

  try {
    const repository = await detectProjectRepository(parsed.data.repoPath)

    return Response.json({
      repository,
      suggestedKey: suggestProjectKey(repository.name),
    })
  } catch (error) {
    if (error instanceof ProjectRepositoryDetectionError) {
      return validationError(error.code, error.message, {
        issues: [
          {
            path: ["repoPath"],
            code: error.code,
            message: error.message,
          },
        ],
      })
    }

    throw error
  }
}

export async function handleCreateProjectRequest(
  request: Request,
  options: AddProjectApiOptions
) {
  const body = await parseJsonRequest(request)

  if (!body.success) {
    return validationError("invalid_request", "Invalid JSON request body")
  }

  const parsed = createProjectRequestSchema.safeParse(body.data)

  if (!parsed.success) {
    if (parsed.error.issues.some((issue) => issue.path[0] === "key")) {
      return validationError("invalid_project_key", PROJECT_KEY_ERROR_MESSAGE, {
        issues: [
          {
            path: ["key"],
            code: "invalid_project_key",
            message: PROJECT_KEY_ERROR_MESSAGE,
          },
        ],
      })
    }

    return validationError("invalid_request", "Invalid Project creation input")
  }

  let repository

  try {
    repository = await detectProjectRepository(parsed.data.repoPath)
  } catch (error) {
    if (error instanceof ProjectRepositoryDetectionError) {
      return validationError(error.code, error.message, {
        issues: [
          {
            path: ["repoPath"],
            code: error.code,
            message: error.message,
          },
        ],
      })
    }

    throw error
  }

  const projects = createProjectRepository({
    databasePath: options.databasePath,
  })
  let project

  try {
    project = await projects.createProject({
      key: parsed.data.key,
      displayName: parsed.data.displayName,
      repoPath: repository.path,
      repositoryMetadata: {
        name: repository.name,
        defaultBranch: repository.defaultBranch,
        remoteUrl: repository.remoteUrl,
        githubSlug: repository.githubSlug,
        packageManagers: repository.packageManagers,
        instructionFiles: repository.instructionFiles,
      },
      defaults: {
        model: defaultCursorModel,
        reasoningLevel: defaultCursorReasoningLevel,
        runTimeoutSeconds: 3600,
      },
      schedule: {
        enabled: false,
        dailyTime: "09:00",
        timezone: "UTC",
        scheduledRunLimit: 1,
      },
    })
  } catch (error) {
    if (
      error instanceof ProjectRepositoryError &&
      error.code === "duplicate_project_key"
    ) {
      return validationError(error.code, error.message, {
        status: 409,
        issues: [
          {
            path: ["key"],
            code: error.code,
            message: error.message,
          },
        ],
      })
    }

    if (
      error instanceof ProjectRepositoryError &&
      error.code === "duplicate_repository_path"
    ) {
      return validationError(error.code, error.message, {
        status: 409,
        issues: [
          {
            path: ["repoPath"],
            code: error.code,
            message: error.message,
          },
        ],
      })
    }

    throw error
  }

  return Response.json(
    {
      project,
      route: {
        projectPath: `/projects/${project.key}`,
      },
    },
    { status: 201 }
  )
}
