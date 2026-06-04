import { GlobalRegistrator } from "@happy-dom/global-registrator"

import assert from "node:assert/strict"
import { afterEach, test } from "node:test"

import { cleanup, render } from "@testing-library/react"
import { mock } from "node:test"

GlobalRegistrator.register()

let databaseStatus: "ready" | "requires_explicit_apply" = "ready"

afterEach(() => {
  cleanup()
  databaseStatus = "ready"
})

mock.module("next/navigation", {
  namedExports: {
    useRouter: () => ({
      push: () => {},
    }),
  },
})

mock.module("@/lib/projects/add-project-api", {
  namedExports: {
    resolveAddProjectApiOptions: async () => ({
      databasePath: "/tmp/operator-test.db",
      databaseStatus,
    }),
  },
})

mock.module("@/components/projects/add-project-form", {
  namedExports: {
    AddProjectForm: () => (
      <form>
        <h2>Add Project</h2>
        <input aria-label="Repository path" />
      </form>
    ),
  },
})

test("Add Project route renders the existing Add Project form when the database is ready", async () => {
  const page = await import("./page.tsx")

  const element = await page.default()
  const view = render(element)

  assert.equal(
    view.getAllByRole("heading", { name: "Add Project", level: 1 }).length,
    1
  )
  assert.ok(view.getByLabelText("Repository path"))
  assert.ok(view.getByText("Add another local Git repository workspace."))
})

test("Add Project route handles explicit database apply state", async () => {
  databaseStatus = "requires_explicit_apply"
  const page = await import("./page.tsx")

  const element = await page.default()
  const view = render(element)

  assert.ok(view.getByRole("alert"))
  assert.equal(view.queryByLabelText("Repository path"), null)
  assert.ok(
    view.getByText(
      "Operator database schema is out of date. Run the explicit database apply command or reset the local Operator database."
    )
  )
})
