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
