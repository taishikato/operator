import { GlobalRegistrator } from "@happy-dom/global-registrator"

import assert from "node:assert/strict"
import { afterEach, test } from "node:test"

import { cleanup, fireEvent, render } from "@testing-library/react"

GlobalRegistrator.register()

afterEach(() => {
  cleanup()
})

test("RawLogViewer supports copying and downloading the raw JSONL text", async () => {
  const { RawLogViewer } = await getRawLogViewer()
  const copied: string[] = []
  Object.defineProperty(navigator, "clipboard", {
    configurable: true,
    value: {
      writeText: async (text: string) => {
        copied.push(text)
      },
    },
  })

  const view = render(
    <RawLogViewer
      runId="run_123"
      initialStatus="review"
      initialRawLogText={'{"type":"run.finished"}\n'}
      pollIntervalMs={5}
    />
  )

  fireEvent.click(view.getByRole("button", { name: "Copy" }))

  assert.deepEqual(copied, ['{"type":"run.finished"}\n'])
  assert.equal(
    view.getByRole("link", { name: "Download" }).getAttribute("download"),
    "run_123.jsonl"
  )
})

test("RawLogViewer polls only while the run is active", async () => {
  const { RawLogViewer } = await getRawLogViewer()
  const originalFetch = globalThis.fetch
  const calls: string[] = []
  globalThis.fetch = (async (input) => {
    calls.push(String(input))
    return new Response(
      JSON.stringify({
        run: { status: "review" },
        rawLogText: '{"type":"run.finished"}\n',
      }),
      { status: 200 }
    )
  }) as typeof fetch

  try {
    const active = render(
      <RawLogViewer
        runId="run_active"
        initialStatus="running"
        initialRawLogText=""
        pollIntervalMs={5}
      />
    )

    await new Promise((resolve) => setTimeout(resolve, 20))
    active.unmount()

    render(
      <RawLogViewer
        runId="run_done"
        initialStatus="review"
        initialRawLogText=""
        pollIntervalMs={5}
      />
    )

    await new Promise((resolve) => setTimeout(resolve, 20))

    assert.equal(calls.includes("/api/runs/run_active"), true)
    assert.equal(calls.includes("/api/runs/run_done"), false)
  } finally {
    globalThis.fetch = originalFetch
  }
})

async function getRawLogViewer() {
  try {
    return await import("./raw-log-viewer.tsx")
  } catch {
    assert.fail("raw-log-viewer component is not implemented yet")
  }
}
