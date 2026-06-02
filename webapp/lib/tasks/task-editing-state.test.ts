import assert from "node:assert/strict"
import { test } from "node:test"

import {
  createTaskEditState,
  discardTaskEditDraft,
  getTaskEditSavePayload,
  hasUnsavedTaskEditChanges,
  updateTaskEditDraft,
} from "./task-editing-state.ts"

test("Task edit state saves and discards explicit draft changes", () => {
  const state = createTaskEditState(savedTask())

  const edited = updateTaskEditDraft(state, {
    title: "Edited title",
    bodyMarkdown: "Edited body",
    acceptanceCriteriaMarkdown: "- Edited criteria",
    modelOverride: "cursor/gpt-5.1",
    reasoningLevelOverride: "medium",
  })

  assert.equal(hasUnsavedTaskEditChanges(edited), true)
  assert.deepEqual(getTaskEditSavePayload(edited), {
    title: "Edited title",
    bodyMarkdown: "Edited body",
    acceptanceCriteriaMarkdown: "- Edited criteria",
    modelOverride: "cursor/gpt-5.1",
    reasoningLevelOverride: "medium",
  })

  const discarded = discardTaskEditDraft(edited)
  assert.equal(hasUnsavedTaskEditChanges(discarded), false)
  assert.equal(discarded.draft.title, "Original title")
  assert.equal(discarded.draft.bodyMarkdown, "Original body")

  const committed = createTaskEditState(edited.draft)
  assert.equal(hasUnsavedTaskEditChanges(committed), false)
  assert.equal(committed.saved.title, "Edited title")
  assert.equal(committed.draft.title, "Edited title")
})

test("unsaved Task edits do not change saved run input", () => {
  const state = createTaskEditState(savedTask())
  const edited = updateTaskEditDraft(state, {
    title: "Unsaved title",
    bodyMarkdown: "Unsaved body",
    acceptanceCriteriaMarkdown: "",
  })

  assert.deepEqual(edited.saved, {
    title: "Original title",
    bodyMarkdown: "Original body",
    acceptanceCriteriaMarkdown: "- Original criteria",
    modelOverride: null,
    reasoningLevelOverride: null,
  })
})

test("stale drawer edit state would save the wrong task without remounting", () => {
  const firstTask = savedTask()
  const secondTask = {
    title: "Second task title",
    bodyMarkdown: "Second body",
    acceptanceCriteriaMarkdown: "- Second criteria",
    modelOverride: null,
    reasoningLevelOverride: null,
  }

  const staleState = updateTaskEditDraft(createTaskEditState(firstTask), {
    title: "Tampered title",
  })

  assert.equal(getTaskEditSavePayload(staleState).title, "Tampered title")
  assert.notEqual(getTaskEditSavePayload(staleState).title, secondTask.title)

  const reinitialized = createTaskEditState(secondTask)
  assert.equal(reinitialized.draft.title, secondTask.title)
  assert.equal(hasUnsavedTaskEditChanges(reinitialized), false)
})

function savedTask() {
  return {
    title: "Original title",
    bodyMarkdown: "Original body",
    acceptanceCriteriaMarkdown: "- Original criteria",
    modelOverride: null,
    reasoningLevelOverride: null,
  }
}
