import assert from "node:assert/strict"
import { test } from "node:test"

import { getTaskDrawerActionState } from "./task-drawer-actions.ts"

test("Ready action stays blocked while draft edits are unsaved", () => {
  const state = getTaskDrawerActionState({
    hasChanges: true,
    isSaving: false,
    isMovingReady: false,
    taskStatus: "backlog",
  })

  assert.equal(state.readyDisabled, true)
  assert.equal(state.readyTitle, "Save your changes before moving to Ready")
  assert.equal(state.saveDisabled, false)
})

test("Save and Ready actions block each other while a request is in flight", () => {
  const whileSaving = getTaskDrawerActionState({
    hasChanges: true,
    isSaving: true,
    isMovingReady: false,
    taskStatus: "backlog",
  })

  assert.equal(whileSaving.isBusy, true)
  assert.equal(whileSaving.readyDisabled, true)
  assert.equal(whileSaving.saveDisabled, true)
  assert.equal(whileSaving.inputsDisabled, true)

  const whileMovingReady = getTaskDrawerActionState({
    hasChanges: false,
    isSaving: false,
    isMovingReady: true,
    taskStatus: "backlog",
  })

  assert.equal(whileMovingReady.isBusy, true)
  assert.equal(whileMovingReady.readyDisabled, true)
  assert.equal(whileMovingReady.saveDisabled, true)
  assert.equal(whileMovingReady.inputsDisabled, true)
})

test("Ready action is available once saved content is unchanged", () => {
  const state = getTaskDrawerActionState({
    hasChanges: false,
    isSaving: false,
    isMovingReady: false,
    taskStatus: "backlog",
  })

  assert.equal(state.readyDisabled, false)
  assert.equal(state.readyTitle, "Move to Ready")
})

test("Create PR action is available only for unchanged Review Tasks with a branch and no PR URL", () => {
  const available = getTaskDrawerActionState({
    hasChanges: false,
    isSaving: false,
    isMovingReady: false,
    isCreatingPullRequest: false,
    taskStatus: "review",
    taskBranchName: "operator/op-1-manual-pr",
    pullRequestUrl: null,
  })

  assert.equal(available.createPullRequestVisible, true)
  assert.equal(available.createPullRequestDisabled, false)
  assert.equal(available.createPullRequestTitle, "Create draft pull request")

  const existingPr = getTaskDrawerActionState({
    hasChanges: false,
    isSaving: false,
    isMovingReady: false,
    isCreatingPullRequest: false,
    taskStatus: "review",
    taskBranchName: "operator/op-1-manual-pr",
    pullRequestUrl: "https://github.com/example/operator/pull/1",
  })

  assert.equal(existingPr.createPullRequestVisible, false)

  const unsaved = getTaskDrawerActionState({
    hasChanges: true,
    isSaving: false,
    isMovingReady: false,
    isCreatingPullRequest: false,
    taskStatus: "review",
    taskBranchName: "operator/op-1-manual-pr",
    pullRequestUrl: null,
  })

  assert.equal(unsaved.createPullRequestVisible, true)
  assert.equal(unsaved.createPullRequestDisabled, true)
  assert.equal(
    unsaved.createPullRequestTitle,
    "Save your changes before creating a pull request"
  )
})

test("Create PR action is blocked when the confirmed title is empty", () => {
  const state = getTaskDrawerActionState({
    hasChanges: false,
    isSaving: false,
    isMovingReady: false,
    isCreatingPullRequest: false,
    taskStatus: "review",
    taskBranchName: "operator/op-1-manual-pr",
    pullRequestUrl: null,
    pullRequestTitle: "   ",
  })

  assert.equal(state.createPullRequestVisible, true)
  assert.equal(state.createPullRequestDisabled, true)
  assert.equal(state.createPullRequestTitle, "Enter a pull request title")
})
