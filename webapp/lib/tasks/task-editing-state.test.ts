import assert from "node:assert/strict"
import { test } from "node:test"

import {
  commitTaskEditDraft,
  createTaskEditState,
  discardTaskEditDraft,
  getSavedTaskRunInput,
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

  const committed = commitTaskEditDraft(edited)
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

  assert.deepEqual(getSavedTaskRunInput(edited), {
    title: "Original title",
    bodyMarkdown: "Original body",
    acceptanceCriteriaMarkdown: "- Original criteria",
    modelOverride: null,
    reasoningLevelOverride: null,
  })
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
