import { GlobalRegistrator } from "@happy-dom/global-registrator"

import assert from "node:assert/strict"
import { afterEach, test } from "node:test"

import { cleanup, render } from "@testing-library/react"
import { mock } from "node:test"

GlobalRegistrator.register()

afterEach(() => {
  cleanup()
})

mock.module("next/navigation", {
  namedExports: {
    notFound: () => {
      throw new Error("not found")
    },
    useRouter: () => ({
      refresh: () => {},
    }),
  },
})

mock.module("next-themes", {
  namedExports: {
    useTheme: () => ({
      theme: "system",
      setTheme: () => {},
    }),
  },
})

mock.module("sonner", {
  namedExports: {
    toast: {
      success: () => {},
      error: () => {},
    },
    Toaster: () => null,
  },
})

mock.module("@/lib/projects/add-project-api", {
  namedExports: {
    resolveAddProjectApiOptions: async () => ({
      databasePath: "/tmp/operator-test.db",
      databaseStatus: "ready",
    }),
  },
})

mock.module("@/lib/projects/project-repository", {
  namedExports: {
    createProjectRepository: () => ({
      getActiveProjectByKey: async () => createProject(),
    }),
  },
})

mock.module("@/lib/app-data/app-data", {
  namedExports: {
    resolveAppDataPaths: () => ({
      appDataDir: "/Users/example/Library/Application Support/Operator",
      databasePath: "/Users/example/Library/Application Support/Operator/operator.db",
      runLogsDir: "/Users/example/Library/Application Support/Operator/runs",
    }),
  },
})

test("Project settings page renders Project and App settings at the settings route", async () => {
  const page = await import("./page.tsx").catch(() => null)

  assert.ok(page)

  const element = await page.default({
    params: Promise.resolve({ projectKey: "OP" }),
  })
  const view = render(element)

  assert.ok(view.getByRole("heading", { name: "Settings" }))
  assert.ok(view.getByRole("tab", { name: "Project" }))
  assert.ok(view.getByRole("tab", { name: "App" }))
  assert.ok(view.getByLabelText("Default model"))
  assert.equal(
    view.getByRole("link", { name: "Back to board" }).getAttribute("href"),
    "/projects/OP"
  )
})

function createProject() {
  return {
    id: "project-id",
    key: "OP",
    displayName: "Operator",
    repoPath: "/Users/example/operator",
    repositoryMetadata: {
      name: "operator",
      defaultBranch: "main",
      remoteUrl: null,
      githubSlug: null,
      packageManagers: ["pnpm"],
      instructionFiles: ["AGENTS.md"],
    },
    defaults: {
      model: "cursor/gpt-5",
      reasoningLevel: "high",
      runTimeoutSeconds: 3600,
    },
    schedule: {
      enabled: false,
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
