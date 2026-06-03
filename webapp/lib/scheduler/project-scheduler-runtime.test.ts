import assert from "node:assert/strict"
import { test } from "node:test"

test("Project scheduler runtime starts one interval and ticks immediately", async () => {
  const runtimeModule = await import("./project-scheduler-runtime.ts").catch(
    () => null
  )

  assert.ok(runtimeModule)

  const intervals: Array<() => void | Promise<void>> = []
  const tickCalls: string[] = []
  const runtime = runtimeModule.createProjectSchedulerRuntime({
    scheduler: {
      async tick() {
        tickCalls.push("tick")
      },
    },
    intervalMs: 60_000,
    setInterval: (callback) => {
      intervals.push(callback)
      return intervals.length
    },
    clearInterval: () => {},
  })

  runtime.start()
  runtime.start()
  await Promise.resolve()

  assert.equal(intervals.length, 1)
  assert.deepEqual(tickCalls, ["tick"])

  await intervals[0]()

  assert.deepEqual(tickCalls, ["tick", "tick"])
})
