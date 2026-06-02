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
