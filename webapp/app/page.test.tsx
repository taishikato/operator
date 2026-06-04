import { GlobalRegistrator } from "@happy-dom/global-registrator"

import assert from "node:assert/strict"
import { afterEach, test } from "node:test"

import { cleanup, render } from "@testing-library/react"
import { mock } from "node:test"

GlobalRegistrator.register()

let databaseStatus: "ready" | "requires_explicit_apply" = "ready"
let activeProjects = [createProject({ key: "OP", scheduleEnabled: false })]
let projectListCount = 0

afterEach(() => {
  cleanup()
  databaseStatus = "ready"
  activeProjects = [createProject({ key: "OP", scheduleEnabled: false })]
  projectListCount = 0
})

mock.module("next/navigation", {
  namedExports: {
    redirect: (route: string) => {
      throw new Error(`unexpected redirect to ${route}`)
    },
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

mock.module("@/lib/projects/project-repository", {
  namedExports: {
    createProjectRepository: () => ({
      listActiveProjects: async () => {
        projectListCount += 1

        return activeProjects
      },
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

test("root route renders Project home when active Projects exist", async () => {
  activeProjects = [
    createProject({ key: "OP", scheduleEnabled: false }),
    createProject({ key: "WEB", scheduleEnabled: true }),
  ]
  const page = await import("./page.tsx")

  const element = await page.default()
  const view = render(element)

  assert.ok(view.getByRole("heading", { name: "Projects" }))
  assert.equal(view.queryByRole("link", { name: "Add Project" }), null)
  assert.ok(view.getByText("/Users/example/operator"))
  assert.ok(view.getByText("Schedule off"))
  assert.ok(view.getByRole("heading", { name: "Operator App" }))
  assert.ok(view.getByRole("heading", { name: "Webapp" }))
  assert.ok(view.getByText("Schedule on"))
  assert.equal(view.queryByText(/^Project /), null)
  assert.equal(
    view.getByRole("link", { name: "Open Operator App" }).getAttribute("href"),
    "/projects/OP"
  )
  assert.equal(
    view.getByRole("link", { name: "Open Webapp" }).getAttribute("href"),
    "/projects/WEB"
  )
})

test("root route renders Add Project form when no active Projects exist", async () => {
  activeProjects = []
  const page = await import("./page.tsx")

  const element = await page.default()
  const view = render(element)

  assert.ok(view.getByRole("heading", { name: "Projects" }))
  assert.ok(view.getByRole("heading", { name: "Add Project" }))
  assert.ok(view.getByLabelText("Repository path"))
  assert.equal(view.queryByRole("link", { name: "Add Project" }), null)
  assert.equal(view.queryByText(/^Project /), null)
})

test("root route shows schema warning before querying Projects", async () => {
  databaseStatus = "requires_explicit_apply"
  const page = await import("./page.tsx")

  const element = await page.default()
  const view = render(element)

  assert.equal(projectListCount, 0)
  assert.ok(view.getByRole("alert"))
  assert.ok(
    view.getByText(
      "Operator database schema is out of date. Run the explicit database apply command or reset the local Operator database."
    )
  )
})

function createProject({
  key,
  scheduleEnabled,
}: {
  key: "OP" | "WEB"
  scheduleEnabled: boolean
}) {
  const nameByKey = {
    OP: "Operator App",
    WEB: "Webapp",
  }
  const pathByKey = {
    OP: "/Users/example/operator",
    WEB: "/Users/example/webapp",
  }

  return {
    id: key,
    key,
    displayName: nameByKey[key],
    repoPath: pathByKey[key],
    repositoryMetadata: {
      name: nameByKey[key].toLowerCase(),
      defaultBranch: "main",
      remoteUrl: null,
      githubSlug: null,
      packageManagers: [],
      instructionFiles: [],
    },
    defaults: {
      model: "gpt-5.5",
      reasoningLevel: "medium",
      runTimeoutSeconds: 3600,
    },
    schedule: {
      enabled: scheduleEnabled,
      dailyTime: "09:00",
      timezone: "UTC",
      scheduledRunLimit: 1,
      lastScheduledLocalDate: null,
    },
    nextTaskNumber: 1,
    createdAt: "2026-06-03T00:00:00.000Z",
    updatedAt: "2026-06-03T00:00:00.000Z",
    removedAt: null,
  }
}
