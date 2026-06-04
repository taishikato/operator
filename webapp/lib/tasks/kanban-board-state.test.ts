import assert from "node:assert/strict"
import { test } from "node:test"

import {
  applyKanbanBoardFailure,
  moveKanbanTask,
} from "./kanban-board-state.ts"
import type { KanbanColumn } from "./kanban-view.ts"

test("moveKanbanTask reorders Tasks within a column without changing other columns", () => {
  const columns = boardColumns({
    backlog: ["OP-1", "OP-2", "OP-3"],
    ready: [],
  })

  const moved = moveKanbanTask(columns, {
    activeDisplayId: "OP-3",
    targetStatus: "backlog",
    targetDisplayId: "OP-1",
  })

  assert.deepEqual(displayIdsByColumn(moved), {
    backlog: ["OP-3", "OP-1", "OP-2"],
    ready: [],
  })
})

test("moveKanbanTask moves same-column Tasks after lower targets", () => {
  const adjacentColumns = boardColumns({
    backlog: ["OP-1", "OP-2", "OP-3"],
    ready: [],
  })

  assert.deepEqual(
    displayIdsByColumn(
      moveKanbanTask(adjacentColumns, {
        activeDisplayId: "OP-1",
        targetStatus: "backlog",
        targetDisplayId: "OP-2",
      })
    ),
    {
      backlog: ["OP-2", "OP-1", "OP-3"],
      ready: [],
    }
  )

  const endColumns = boardColumns({
    backlog: ["OP-1", "OP-2", "OP-3"],
    ready: [],
  })

  assert.deepEqual(
    displayIdsByColumn(
      moveKanbanTask(endColumns, {
        activeDisplayId: "OP-1",
        targetStatus: "backlog",
        targetDisplayId: "OP-3",
      })
    ),
    {
      backlog: ["OP-2", "OP-3", "OP-1"],
      ready: [],
    }
  )
})

test("applyKanbanBoardFailure restores the last server-backed columns and reports the error", () => {
  const lastServerColumns = boardColumns({
    backlog: ["OP-1", "OP-2"],
    ready: [],
  })
  const optimisticColumns = boardColumns({
    backlog: ["OP-2"],
    ready: ["OP-1"],
  })

  const recovered = applyKanbanBoardFailure({
    lastServerColumns,
    optimisticColumns,
    message: "Could not save board order.",
  })

  assert.deepEqual(displayIdsByColumn(recovered.columns), {
    backlog: ["OP-1", "OP-2"],
    ready: [],
  })
  assert.equal(recovered.errorMessage, "Could not save board order.")
})

function boardColumns(input: {
  backlog: string[]
  ready: string[]
}): KanbanColumn[] {
  return [
    {
      status: "backlog",
      label: "Backlog",
      tasks: input.backlog.map((displayId, index) =>
        task(displayId, "backlog", index + 1)
      ),
    },
    {
      status: "ready",
      label: "Ready",
      tasks: input.ready.map((displayId, index) =>
        task(displayId, "ready", index + 1)
      ),
    },
  ]
}

function task(
  displayId: string,
  status: "backlog" | "ready",
  position: number
) {
  return {
    id: displayId,
    displayId,
    title: displayId,
    bodyMarkdown: "",
    acceptanceCriteriaMarkdown: "",
    status,
    position,
    taskBranchName: null,
    pullRequestUrl: null,
    pullRequestError: null,
    modelOverride: null,
    reasoningLevelOverride: null,
  }
}

function displayIdsByColumn(columns: KanbanColumn[]) {
  return Object.fromEntries(
    columns.map((column) => [
      column.status,
      column.tasks.map((task) => task.displayId),
    ])
  )
}
