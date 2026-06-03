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

test("KanbanBoard exposes Run Now for runnable Tasks only", async () => {
  const { KanbanBoard } = await import("./kanban-board.tsx")
  const view = render(
    <KanbanBoard
      projectKey="OP"
      initialColumns={boardColumns({
        backlog: ["OP-1"],
        ready: ["OP-2"],
        running: ["OP-3"],
        review: ["OP-4"],
        done: ["OP-5"],
        blocked: ["OP-6"],
      })}
    />
  )

  assert.equal(view.queryByRole("button", { name: "Run OP-1" }) !== null, true)
  assert.equal(view.queryByRole("button", { name: "Run OP-2" }) !== null, true)
  assert.equal(view.queryByRole("button", { name: "Run OP-4" }) !== null, true)
  assert.equal(view.queryByRole("button", { name: "Run OP-6" }) !== null, true)
  assert.equal(view.queryByRole("button", { name: "Run OP-3" }), null)
  assert.equal(view.queryByRole("button", { name: "Run OP-5" }), null)
})

function boardColumns(input: {
  backlog?: string[]
  ready?: string[]
  running?: string[]
  review?: string[]
  done?: string[]
  blocked?: string[]
}): KanbanColumn[] {
  return [
    {
      status: "backlog",
      label: "Backlog",
      tasks: (input.backlog ?? []).map((displayId, index) =>
        task(displayId, "backlog", index + 1)
      ),
    },
    {
      status: "ready",
      label: "Ready",
      tasks: (input.ready ?? []).map((displayId, index) =>
        task(displayId, "ready", index + 1)
      ),
    },
    {
      status: "running",
      label: "Running",
      tasks: (input.running ?? []).map((displayId, index) =>
        task(displayId, "running", index + 1)
      ),
    },
    {
      status: "review",
      label: "Review",
      tasks: (input.review ?? []).map((displayId, index) =>
        task(displayId, "review", index + 1)
      ),
    },
    {
      status: "done",
      label: "Done",
      tasks: (input.done ?? []).map((displayId, index) =>
        task(displayId, "done", index + 1)
      ),
    },
    {
      status: "blocked",
      label: "Blocked",
      tasks: (input.blocked ?? []).map((displayId, index) =>
        task(displayId, "blocked", index + 1)
      ),
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
