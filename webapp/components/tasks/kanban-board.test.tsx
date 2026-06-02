import { GlobalRegistrator } from "@happy-dom/global-registrator"

import assert from "node:assert/strict"
import { afterEach, mock, test } from "node:test"

import { cleanup, render } from "@testing-library/react"

import type { KanbanColumn } from "@/lib/tasks/kanban-view.ts"
import type { TaskStatus } from "@/lib/tasks/task-repository.ts"

GlobalRegistrator.register()

afterEach(() => {
  cleanup()
})

mock.module("next/navigation", {
  namedExports: {
    useRouter: () => ({
      refresh: () => {},
    }),
  },
})

test("KanbanBoard shows server-refreshed Tasks when initial columns change", async () => {
  const { KanbanBoard } = await import("./kanban-board.tsx")
  const view = render(
    <KanbanBoard
      projectKey="OP"
      initialColumns={boardColumns({ backlog: ["OP-1"] })}
    />
  )

  assert.equal(view.queryAllByText("OP-1").length, 2)
  assert.equal(view.queryAllByText("OP-2").length, 0)

  view.rerender(
    <KanbanBoard
      projectKey="OP"
      initialColumns={boardColumns({ backlog: ["OP-1", "OP-2"] })}
    />
  )

  assert.equal(view.queryAllByText("OP-2").length, 2)
})

function boardColumns(input: { backlog: string[] }): KanbanColumn[] {
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
      tasks: [],
    },
    {
      status: "running",
      label: "Running",
      tasks: [],
    },
    {
      status: "review",
      label: "Review",
      tasks: [],
    },
    {
      status: "done",
      label: "Done",
      tasks: [],
    },
    {
      status: "blocked",
      label: "Blocked",
      tasks: [],
    },
  ]
}

function task(displayId: string, status: TaskStatus, position: number) {
  return {
    id: displayId,
    displayId,
    title: displayId,
    bodyMarkdown: "",
    acceptanceCriteriaMarkdown: "",
    status,
    position,
    modelOverride: null,
    reasoningLevelOverride: null,
  }
}
