import { GlobalRegistrator } from "@happy-dom/global-registrator"

import assert from "node:assert/strict"
import { afterEach, test } from "node:test"

import { cleanup, fireEvent, render } from "@testing-library/react"
import { mock } from "node:test"

GlobalRegistrator.register()

const themeCalls: string[] = []

afterEach(() => {
  cleanup()
  themeCalls.length = 0
})

mock.module("next/navigation", {
  namedExports: {
    useRouter: () => ({
      refresh: () => {},
    }),
  },
})

mock.module("next-themes", {
  namedExports: {
    useTheme: () => ({
      theme: "system",
      setTheme: (theme: string) => {
        themeCalls.push(theme)
      },
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

test("ProjectSettingsPanel exposes Project and App tabs with operational status and theme controls", async () => {
  const component = await import("./project-settings-panel.tsx").catch(
    () => null
  )

  assert.ok(component)

  const view = render(
    <component.ProjectSettingsPanel
      projectKey="OP"
      project={createProjectSettings()}
      appStatus={{
        appDataDir: "/Users/example/Library/Application Support/Operator",
        cursorApiKeyStatus: "configured",
        version: "0.0.1",
      }}
    />
  )

  assert.ok(view.getByRole("tab", { name: "Project" }))
  assert.ok(view.getByRole("tab", { name: "App" }))
  assert.ok(view.getByLabelText("Default model"))

  fireEvent.click(view.getByRole("tab", { name: "App" }))

  assert.ok(
    view.getByText("/Users/example/Library/Application Support/Operator")
  )
  assert.ok(view.getByText("configured"))
  assert.ok(view.getByText("0.0.1"))
  assert.ok(view.getByRole("button", { name: "System" }))
  assert.ok(view.getByRole("button", { name: "Light" }))
  assert.ok(view.getByRole("button", { name: "Dark" }))
  assert.throws(() => view.getByLabelText("Default model"))
  assert.throws(() => view.getByLabelText("Default reasoning"))

  fireEvent.click(view.getByRole("button", { name: "Dark" }))

  assert.deepEqual(themeCalls, ["dark"])
})

function createProjectSettings() {
  return {
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
    },
  }
}
