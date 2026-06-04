import assert from "node:assert/strict"
import { test } from "node:test"

import {
  applyCreateProjectError,
  applyDetectProjectError,
  applyDetectProjectSuccess,
  applyProjectKeyChange,
  applyRepositoryPathChange,
  canSubmitAddProjectForm,
  createInitialAddProjectFormState,
} from "./add-project-ui-state.ts"

test("applyDetectProjectSuccess previews repository metadata and prefills editable fields", () => {
  const state = applyDetectProjectSuccess(
    {
      ...createInitialAddProjectFormState(),
      repoPath: "/Users/example/operator",
    },
    {
      repository: {
        path: "/Users/example/operator",
        name: "operator",
        defaultBranch: "main",
        remoteUrl: "git@github.com:example/operator.git",
        githubSlug: "example/operator",
        packageManagers: ["pnpm"],
        instructionFiles: ["AGENTS.md"],
      },
      suggestedKey: "OP",
    }
  )

  assert.equal(state.repoPath, "/Users/example/operator")
  assert.equal(state.key, "OP")
  assert.equal(state.displayName, "operator")
  assert.equal(state.errorMessage, null)
  assert.deepEqual(state.repositoryPreview, {
    path: "/Users/example/operator",
    name: "operator",
    defaultBranch: "main",
    remoteUrl: "git@github.com:example/operator.git",
    githubSlug: "example/operator",
    packageManagers: ["pnpm"],
    instructionFiles: ["AGENTS.md"],
  })
})

test("applyDetectProjectError shows validation errors without clearing entered form data", () => {
  const state = applyDetectProjectError(
    {
      ...createInitialAddProjectFormState(),
      repoPath: "/Users/example/not-a-repo",
      key: "custom",
      displayName: "Custom Project",
    },
    {
      error: {
        code: "not_git_repository",
        message: "Path is not a Git repository",
      },
    }
  )

  assert.equal(state.repoPath, "/Users/example/not-a-repo")
  assert.equal(state.key, "custom")
  assert.equal(state.displayName, "Custom Project")
  assert.equal(state.errorMessage, "Path is not a Git repository")
})

test("applyCreateProjectError keeps detected metadata and editable key visible", () => {
  const detected = applyDetectProjectSuccess(
    createInitialAddProjectFormState(),
    {
      repository: {
        path: "/Users/example/operator",
        name: "operator",
        defaultBranch: "main",
        remoteUrl: null,
        githubSlug: null,
        packageManagers: [],
        instructionFiles: [],
      },
      suggestedKey: "OP",
    }
  )

  const state = applyCreateProjectError(
    { ...detected, key: "bad key" },
    {
      error: {
        code: "invalid_project_key",
        message:
          "Project key must be 1-32 lowercase letters, numbers, or hyphens.",
      },
    }
  )

  assert.equal(state.key, "bad key")
  assert.equal(state.displayName, "operator")
  assert.equal(state.repositoryPreview?.path, "/Users/example/operator")
  assert.equal(
    state.errorMessage,
    "Project key must be 1-32 lowercase letters, numbers, or hyphens."
  )
})

test("applyRepositoryPathChange clears detected metadata when the path changes", () => {
  const detected = applyDetectProjectSuccess(
    createInitialAddProjectFormState(),
    {
      repository: {
        path: "/Users/example/operator",
        name: "operator",
        defaultBranch: "main",
        remoteUrl: null,
        githubSlug: null,
        packageManagers: [],
        instructionFiles: [],
      },
      suggestedKey: "OP",
    }
  )

  const state = applyRepositoryPathChange(detected, "/Users/example/other-repo")

  assert.equal(state.repoPath, "/Users/example/other-repo")
  assert.equal(state.key, "")
  assert.equal(state.displayName, "")
  assert.equal(state.repositoryPreview, null)
  assert.equal(state.errorMessage, null)
})

test("applyProjectKeyChange stores manually entered Project keys in lowercase", () => {
  const state = applyProjectKeyChange(createInitialAddProjectFormState(), "op1")

  assert.equal(state.key, "op1")
})

test("canSubmitAddProjectForm does not require a detected repository preview", () => {
  assert.equal(
    canSubmitAddProjectForm(
      {
        ...createInitialAddProjectFormState(),
        repoPath: "/Users/example/skills",
        key: "skills",
        displayName: "skills",
        repositoryPreview: null,
      },
      false
    ),
    true
  )
})
