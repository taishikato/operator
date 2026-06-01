import assert from "node:assert/strict"
import { test } from "node:test"

import {
  applyCreateProjectError,
  applyDetectProjectError,
  applyDetectProjectSuccess,
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
      key: "CUSTOM",
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
  assert.equal(state.key, "CUSTOM")
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
        message: "Project key must be 1-6 uppercase letters or numbers.",
      },
    }
  )

  assert.equal(state.key, "bad key")
  assert.equal(state.displayName, "operator")
  assert.equal(state.repositoryPreview?.path, "/Users/example/operator")
  assert.equal(
    state.errorMessage,
    "Project key must be 1-6 uppercase letters or numbers."
  )
})
