import { test } from "node:test"
import assert from "node:assert/strict"

import {
  resetCliManagedServerRuntimeForTests,
  startCliManagedServerRuntime,
} from "./operator-server-runtime.ts"

test("startCliManagedServerRuntime does nothing outside CLI-managed startup", async () => {
  const events: string[] = []

  await startCliManagedServerRuntime({
    env: {},
    bootstrapDatabase: async () => {
      events.push("bootstrap")
      return {
        databasePath: "/tmp/operator.db",
        schemaApplied: false,
        status: "ready",
      }
    },
    reconcileStaleRuns: async () => {
      events.push("reconcile")
      return { interruptedRuns: 0 }
    },
    startScheduler: () => {
      events.push("scheduler")
    },
  })

  assert.deepEqual(events, [])
})

test("startCliManagedServerRuntime starts startup work once in the Next server process", async () => {
  resetCliManagedServerRuntimeForTests()
  const events: string[] = []

  const dependencies = {
    env: { OPERATOR_CLI_MANAGED_START: "1" },
    bootstrapDatabase: async () => {
      events.push("bootstrap")
      return {
        databasePath: "/tmp/operator.db",
        schemaApplied: true,
        status: "initialized" as const,
      }
    },
    reconcileStaleRuns: async (databasePath: string) => {
      events.push(`reconcile:${databasePath}`)
      return { interruptedRuns: 0 }
    },
    startScheduler: ({ databasePath }: { databasePath: string }) => {
      events.push(`scheduler:${databasePath}`)
    },
  }

  await startCliManagedServerRuntime(dependencies)
  await startCliManagedServerRuntime(dependencies)

  assert.deepEqual(events, [
    "bootstrap",
    "reconcile:/tmp/operator.db",
    "scheduler:/tmp/operator.db",
  ])
})
