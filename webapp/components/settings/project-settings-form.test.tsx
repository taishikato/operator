import { GlobalRegistrator } from "@happy-dom/global-registrator"

import assert from "node:assert/strict"
import { afterEach, test } from "node:test"

import { cleanup, fireEvent, render, waitFor } from "@testing-library/react"
import { mock } from "node:test"

GlobalRegistrator.register()

const toastCalls: Array<{ type: "success" | "error"; message: string }> = []

afterEach(() => {
  cleanup()
  toastCalls.length = 0
})

mock.module("next/navigation", {
  namedExports: {
    useRouter: () => ({
      refresh: () => {},
    }),
  },
})

mock.module("sonner", {
  namedExports: {
    toast: {
      success: (message: string) => {
        toastCalls.push({ type: "success", message })
      },
      error: (message: string) => {
        toastCalls.push({ type: "error", message })
      },
    },
    Toaster: () => null,
  },
})

test("ProjectSettingsForm waits for explicit Save before persisting changes and reports success", async () => {
  const component = await import("./project-settings-form.tsx").catch(
    () => null
  )

  assert.ok(component)

  const fetchCalls: Array<{ input: RequestInfo | URL; init?: RequestInit }> = []
  const originalFetch = globalThis.fetch
  globalThis.fetch = (async (input, init) => {
    fetchCalls.push({ input, init })

    return new Response(
      JSON.stringify({
        project: {
          defaults: {
            model: "gpt-5.5",
            reasoningLevel: "medium",
            runTimeoutSeconds: 1800,
          },
          schedule: {
            enabled: true,
            dailyTime: "10:30",
            timezone: "Asia/Tokyo",
            scheduledRunLimit: 4,
            lastScheduledLocalDate: null,
          },
        },
      }),
      { status: 200 }
    )
  }) as typeof fetch

  try {
    const view = render(
      <component.ProjectSettingsForm
        projectKey="OP"
        project={createProjectSettings()}
      />
    )

    fireEvent.change(view.getByLabelText("Default model"), {
      target: { value: "opus-4.8" },
    })

    assert.equal(fetchCalls.length, 0)

    await waitFor(() =>
      assert.equal(
        (view.getByRole("button", { name: "Save" }) as HTMLButtonElement)
          .disabled,
        false
      )
    )

    fireEvent.click(view.getByRole("button", { name: "Save" }))

    await waitFor(() => assert.equal(fetchCalls.length, 1))
    assert.equal(fetchCalls[0]?.input, "/api/projects/OP/settings")
    assert.equal(fetchCalls[0]?.init?.method, "PATCH")
    assert.deepEqual(JSON.parse(fetchCalls[0]?.init?.body as string), {
      defaultModel: "opus-4.8",
      defaultReasoningLevel: "high",
      scheduleEnabled: false,
      scheduleDailyTime: "09:00",
      scheduleTimezone: "UTC",
      scheduledRunLimit: 1,
      runTimeoutSeconds: 3600,
    })
    assert.deepEqual(toastCalls, [
      { type: "success", message: "Project settings saved." },
    ])
  } finally {
    globalThis.fetch = originalFetch
  }
})

test("ProjectSettingsForm reports validation failure with a toast", async () => {
  const component = await import("./project-settings-form.tsx").catch(
    () => null
  )

  assert.ok(component)

  const originalFetch = globalThis.fetch
  globalThis.fetch = (async () =>
    new Response(
      JSON.stringify({
        error: {
          code: "invalid_project_settings",
          message: "Invalid Project settings input",
        },
      }),
      { status: 400 }
    )) as typeof fetch

  try {
    const view = render(
      <component.ProjectSettingsForm
        projectKey="OP"
        project={createProjectSettings()}
      />
    )

    fireEvent.input(view.getByLabelText("Daily time"), {
      target: { value: "25:99" },
    })
    await waitFor(() =>
      assert.equal(
        (view.getByRole("button", { name: "Save" }) as HTMLButtonElement)
          .disabled,
        false
      )
    )
    fireEvent.click(view.getByRole("button", { name: "Save" }))

    await waitFor(() =>
      assert.deepEqual(toastCalls, [
        { type: "error", message: "Invalid Project settings input" },
      ])
    )
  } finally {
    globalThis.fetch = originalFetch
  }
})

test("ProjectSettingsForm mirrors the server run timeout range in the number input", async () => {
  const component = await import("./project-settings-form.tsx").catch(
    () => null
  )

  assert.ok(component)

  const view = render(
    <component.ProjectSettingsForm
      projectKey="OP"
      project={createProjectSettings()}
    />
  )

  const runTimeoutInput = view.getByLabelText(
    "Run timeout seconds"
  ) as HTMLInputElement

  assert.equal(runTimeoutInput.min, "60")
  assert.equal(runTimeoutInput.max, "86400")
})

test("ProjectSettingsForm disables reasoning and saves default for Composer", async () => {
  const component = await import("./project-settings-form.tsx").catch(
    () => null
  )

  assert.ok(component)

  const fetchCalls: Array<{ input: RequestInfo | URL; init?: RequestInit }> = []
  const originalFetch = globalThis.fetch
  globalThis.fetch = (async (input, init) => {
    fetchCalls.push({ input, init })

    return new Response(
      JSON.stringify({
        project: {
          defaults: {
            model: "composer-2.5",
            reasoningLevel: "default",
            runTimeoutSeconds: 3600,
          },
          schedule: {
            enabled: false,
            dailyTime: "09:00",
            timezone: "UTC",
            scheduledRunLimit: 1,
          },
        },
      }),
      { status: 200 }
    )
  }) as typeof fetch

  try {
    const view = render(
      <component.ProjectSettingsForm
        projectKey="OP"
        project={createProjectSettings()}
      />
    )

    fireEvent.change(view.getByLabelText("Default model"), {
      target: { value: "composer-2.5" },
    })

    const reasoningSelect = view.getByLabelText(
      "Default reasoning"
    ) as HTMLSelectElement

    assert.equal(reasoningSelect.value, "default")
    assert.equal(reasoningSelect.disabled, true)

    fireEvent.click(view.getByRole("button", { name: "Save" }))

    await waitFor(() => assert.equal(fetchCalls.length, 1))
    assert.equal(
      JSON.parse(fetchCalls[0]?.init?.body as string).defaultReasoningLevel,
      "default"
    )
  } finally {
    globalThis.fetch = originalFetch
  }
})

function createProjectSettings() {
  return {
    defaults: {
      model: "gpt-5.5",
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
