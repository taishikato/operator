import { GlobalRegistrator } from "@happy-dom/global-registrator"

import assert from "node:assert/strict"
import { afterEach, test } from "node:test"

import { cleanup, fireEvent, render } from "@testing-library/react"
import { mock } from "node:test"

import { taskDrawerRemountKey } from "@/lib/tasks/task-drawer-mount.ts"
import type { TaskStatus } from "@/lib/tasks/task-repository.ts"

GlobalRegistrator.register()

type DrawerTask = {
  displayId: string
  title: string
  bodyMarkdown: string
  acceptanceCriteriaMarkdown: string
  status: TaskStatus
  modelOverride: string | null
  reasoningLevelOverride: string | null
  latestRun: {
    id: string
    status: string
    blockedReason: string | null
    startedAt: string
    finishedAt: string | null
    updatedAt: string
    rawLogPath: string
  } | null
}

function createDrawerTask(
  displayId: string,
  title: string
): DrawerTask {
  return {
    displayId,
    title,
    bodyMarkdown: `${title} body`,
    acceptanceCriteriaMarkdown: "",
    status: "backlog",
    modelOverride: null,
    reasoningLevelOverride: null,
    latestRun: null,
  }
}

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

test("Save stays disabled while Ready move is in flight", async () => {
  const { TaskDrawer } = await import("./task-drawer.tsx")

  const task = createDrawerTask("OP-1", "First task")
  let resolveReady: (response: Response) => void = () => {}
  const readyResponse = new Promise<Response>((resolve) => {
    resolveReady = resolve
  })

  const originalFetch = globalThis.fetch
  globalThis.fetch = (async (input, init) => {
    const body =
      typeof init?.body === "string" ? JSON.parse(init.body) : undefined

    if (init?.method === "PATCH" && body?.status === "ready") {
      return readyResponse
    }

    return originalFetch(input, init)
  }) as typeof fetch

  try {
    const view = render(<TaskDrawer projectKey="demo" task={task} />)

    const readyButton = view.getByRole("button", { name: "Ready" })

    fireEvent.click(readyButton)

    const saveButtonWhileBusy = view.getByRole("button", { name: "Save" })
    const readyButtonWhileBusy = view.getByRole("button", { name: "Ready" })
    const titleInputWhileBusy =
      view.getByDisplayValue("First task") as HTMLInputElement

    assert.equal((readyButtonWhileBusy as HTMLButtonElement).disabled, true)
    assert.equal((saveButtonWhileBusy as HTMLButtonElement).disabled, true)
    assert.equal(titleInputWhileBusy.disabled, true)

    resolveReady(
      new Response(
        JSON.stringify({
          task: {
            ...task,
            status: "ready",
          },
        }),
        { status: 200 }
      )
    )

    await new Promise((resolve) => setTimeout(resolve, 0))

    view.rerender(
      <TaskDrawer
        projectKey="demo"
        task={{
          ...task,
          status: "ready",
        }}
      />
    )

    const saveButtonAfterReady = view.getByRole("button", { name: "Save" })
    const readyButtonAfterReady = view.getByRole("button", { name: "Ready" })
    const titleInputAfterReady =
      view.getByDisplayValue("First task") as HTMLInputElement

    assert.equal((readyButtonAfterReady as HTMLButtonElement).disabled, true)
    assert.equal((saveButtonAfterReady as HTMLButtonElement).disabled, true)
    assert.equal(titleInputAfterReady.disabled, false)
  } finally {
    globalThis.fetch = originalFetch
  }
})

test("selected task drawer remount clears stale edit draft when task changes", async () => {
  const { TaskDrawer } = await import("./task-drawer.tsx")

  const firstTask = createDrawerTask("OP-1", "First task")
  const secondTask = createDrawerTask("OP-2", "Second task")

  function SelectedTaskDrawer({ task }: { task: DrawerTask }) {
    return (
      <TaskDrawer
        key={taskDrawerRemountKey(task.displayId)}
        projectKey="demo"
        task={task}
      />
    )
  }

  const view = render(<SelectedTaskDrawer task={firstTask} />)

  fireEvent.change(view.getByDisplayValue("First task"), {
    target: { value: "Tampered title" },
  })

  view.rerender(<SelectedTaskDrawer task={secondTask} />)

  assert.equal(
    (view.getByDisplayValue("Second task") as HTMLInputElement).value,
    "Second task"
  )
  assert.throws(() => view.getByDisplayValue("Tampered title"))
})

test("task drawer shows latest run summary and raw log link", async () => {
  const { TaskDrawer } = await import("./task-drawer.tsx")

  const task = {
    ...createDrawerTask("OP-1", "First task"),
    latestRun: {
      id: "run_123",
      status: "blocked",
      blockedReason: "agent_error",
      startedAt: "2026-06-01T00:00:00.000Z",
      finishedAt: "2026-06-01T00:01:00.000Z",
      updatedAt: "2026-06-01T00:01:00.000Z",
      rawLogPath: "/runs/run_123",
    },
  }

  const view = render(<TaskDrawer projectKey="demo" task={task} />)

  assert.match(view.getByText("Latest run").textContent ?? "", /Latest run/)
  assert.match(view.getByText("blocked").textContent ?? "", /blocked/)
  assert.match(view.getByText("agent_error").textContent ?? "", /agent_error/)
  assert.equal(
    view.getByRole("link", { name: "Raw log" }).getAttribute("href"),
    "/runs/run_123"
  )
})
