import type { ProjectRepositoryMetadata } from "./detect-project-repository.ts"

export type AddProjectApiErrorBody = {
  error?: {
    code?: string
    message?: string
  }
}

export type DetectProjectSuccessBody = {
  repository: ProjectRepositoryMetadata
  suggestedKey: string
}

export type AddProjectFormState = {
  repoPath: string
  key: string
  displayName: string
  repositoryPreview: ProjectRepositoryMetadata | null
  errorMessage: string | null
}

export function createInitialAddProjectFormState(): AddProjectFormState {
  return {
    repoPath: "",
    key: "",
    displayName: "",
    repositoryPreview: null,
    errorMessage: null,
  }
}

export function applyDetectProjectSuccess(
  state: AddProjectFormState,
  body: DetectProjectSuccessBody
): AddProjectFormState {
  return {
    ...state,
    repoPath: body.repository.path,
    key: body.suggestedKey,
    displayName: body.repository.name,
    repositoryPreview: body.repository,
    errorMessage: null,
  }
}

export function applyRepositoryPathChange(
  state: AddProjectFormState,
  repoPath: string
): AddProjectFormState {
  if (repoPath === state.repoPath) {
    return {
      ...state,
      repoPath,
    }
  }

  return {
    ...state,
    repoPath,
    key: "",
    displayName: "",
    repositoryPreview: null,
    errorMessage: null,
  }
}

export function applyProjectKeyChange(
  state: AddProjectFormState,
  key: string
): AddProjectFormState {
  return {
    ...state,
    key: key.toUpperCase(),
  }
}

export function applyDetectProjectError(
  state: AddProjectFormState,
  body: AddProjectApiErrorBody
): AddProjectFormState {
  return {
    ...state,
    errorMessage: errorMessage(body),
  }
}

export function applyCreateProjectError(
  state: AddProjectFormState,
  body: AddProjectApiErrorBody
): AddProjectFormState {
  return {
    ...state,
    errorMessage: errorMessage(body),
  }
}

function errorMessage(body: AddProjectApiErrorBody) {
  return body.error?.message ?? "The request failed."
}
