import assert from "node:assert/strict"
import { test } from "node:test"

import {
  createKanbanColumns,
  resolveTaskDrawer,
  type KanbanTask,
} from "./kanban-view.ts"

test("createKanbanColumns exposes the MVP columns and places Backlog Tasks in the first column", () => {
  const columns = createKanbanColumns([task({ displayId: "OP-1" })])

  assert.deepEqual(
    columns.map((column) => column.label),
    ["Backlog", "Ready", "Running", "Review", "Done", "Blocked"]
  )
  assert.deepEqual(
    columns.map((column) => column.tasks.map((task) => task.displayId)),
    [["OP-1"], [], [], [], [], []]
  )
})

test("resolveTaskDrawer selects a Task by display ID from the URL query", () => {
  const selected = resolveTaskDrawer("OP-1", [
    task({ displayId: "OP-1", title: "Selected task" }),
    task({ displayId: "OP-2", title: "Other task" }),
  ])

  assert.equal(selected?.displayId, "OP-1")
  assert.equal(selected?.title, "Selected task")
  assert.equal(resolveTaskDrawer("OP-404", [task({ displayId: "OP-1" })]), null)
  assert.equal(resolveTaskDrawer(undefined, [task({ displayId: "OP-1" })]), null)
})

function task(overrides: Partial<KanbanTask> = {}): KanbanTask {
  return {
    id: "task-id",
    displayId: "OP-1",
    title: "Task title",
    bodyMarkdown: "Task body",
    acceptanceCriteriaMarkdown: "- Acceptance criteria",
    status: "backlog",
    position: 1,
    ...overrides,
  }
}
