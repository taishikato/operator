import assert from "node:assert/strict"
import { test } from "node:test"

import {
  attachLatestRunSummaries,
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

test("attachLatestRunSummaries adds the latest Run summary to matching Tasks", () => {
  const tasks = [
    task({ id: "task-1", displayId: "OP-1" }),
    task({ id: "task-2", displayId: "OP-2" }),
  ]
  const withRuns = attachLatestRunSummaries(tasks, {
    "task-1": {
      id: "run_1",
      status: "review",
      blockedReason: null,
      startedAt: "2026-06-01T00:00:00.000Z",
      finishedAt: "2026-06-01T00:01:00.000Z",
      updatedAt: "2026-06-01T00:01:00.000Z",
      rawLogPath: "/runs/run_1",
    },
  })

  assert.equal(withRuns[0]?.latestRun?.id, "run_1")
  assert.equal(withRuns[1]?.latestRun, null)
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
    modelOverride: null,
    reasoningLevelOverride: null,
    latestRun: null,
    ...overrides,
  }
}
