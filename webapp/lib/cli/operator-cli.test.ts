import { test } from "node:test"
import assert from "node:assert/strict"

import {
  startNextProductionServer,
  runOperatorCli,
  type OperatorCliDependencies,
} from "./operator-cli.ts"

test("operator start defaults to 127.0.0.1:3927 and prints the local URL", async () => {
  const events: string[] = []

  const result = await runOperatorCli(
    ["start"],
    makeDependencies(events, {
      reconcileStaleRuns: async () => {
        events.push("reconcile")
        return { interruptedRuns: 0 }
      },
      startScheduler: () => {
        events.push("scheduler")
      },
      startServer: async ({ host, port }) => {
        events.push(`server:${host}:${port}`)
        return {
          url: `http://${host}:${port}`,
          stop: async () => {
            events.push("stop")
          },
        }
      },
      writeStdout: (message) => {
        events.push(`stdout:${message}`)
      },
      writeStderr: (message) => {
        events.push(`stderr:${message}`)
      },
    })
  )

  assert.equal(result.exitCode, 0)
  assert.deepEqual(events, [
    "reconcile",
    "scheduler",
    "server:127.0.0.1:3927",
    "stdout:Operator is running at http://127.0.0.1:3927\n",
  ])
})

test("operator start reports a clear error when the default port is already in use", async () => {
  const events: string[] = []
  const portError = Object.assign(new Error("listen EADDRINUSE"), {
    code: "EADDRINUSE",
  })

  const result = await runOperatorCli(
    ["start"],
    makeDependencies(events, {
      startServer: async () => {
        throw portError
      },
    })
  )

  assert.equal(result.exitCode, 1)
  assert.deepEqual(events, [
    "stderr:Port 3927 is already in use on 127.0.0.1. Stop the other process and run operator start again.\n",
  ])
})

test("operator start --open opens the browser after the startup URL is known", async () => {
  const events: string[] = []

  const result = await runOperatorCli(
    ["start", "--open"],
    makeDependencies(events, {
      startServer: async ({ host, port }) => {
        events.push("server")
        return {
          url: `http://${host}:${port}`,
        }
      },
      openBrowser: async (url) => {
        events.push(`open:${url}`)
      },
    })
  )

  assert.equal(result.exitCode, 0)
  assert.deepEqual(events, [
    "server",
    "stdout:Operator is running at http://127.0.0.1:3927\n",
    "open:http://127.0.0.1:3927",
  ])
})

test("operator db apply runs the explicit schema apply path and reports the database path", async () => {
  const events: string[] = []

  const result = await runOperatorCli(
    ["db", "apply"],
    makeDependencies(events, {
      applyDatabaseSchema: async () => {
        events.push("apply")
        return {
          databasePath: "/tmp/operator.db",
          schemaApplied: true,
          status: "applied",
        }
      },
    })
  )

  assert.equal(result.exitCode, 0)
  assert.deepEqual(events, [
    "apply",
    "stdout:Operator database schema applied at /tmp/operator.db\n",
  ])
})

test("startNextProductionServer owns next start on the requested host and port", async () => {
  const spawned: Array<{ command: string; args: string[] }> = []

  const result = await startNextProductionServer({
    host: "127.0.0.1",
    port: 3927,
    ensurePortAvailable: async () => undefined,
    runProcess: async ({ command, args }) => {
      spawned.push({ command, args })
      return { exitCode: 0 }
    },
  })

  assert.equal(result.url, "http://127.0.0.1:3927")
  assert.deepEqual(spawned, [
    {
      command: "pnpm",
      args: ["exec", "next", "start", "-H", "127.0.0.1", "-p", "3927"],
    },
  ])
})

test("startNextProductionServer checks port availability before spawning next", async () => {
  const spawned: string[] = []
  const portError = Object.assign(new Error("busy"), { code: "EADDRINUSE" })

  await assert.rejects(
    startNextProductionServer({
      host: "127.0.0.1",
      port: 3927,
      ensurePortAvailable: async () => {
        throw portError
      },
      runProcess: async ({ command }) => {
        spawned.push(command)
      },
    }),
    portError
  )
  assert.deepEqual(spawned, [])
})

function makeDependencies(
  events: string[],
  overrides: Partial<OperatorCliDependencies> = {}
): OperatorCliDependencies {
  return {
    bootstrapDatabase: async () => ({
      databasePath: "/tmp/operator.db",
      schemaApplied: true,
      status: "initialized",
    }),
    reconcileStaleRuns: async () => ({ interruptedRuns: 0 }),
    startScheduler: () => undefined,
    startServer: async ({ host, port }) => ({
      url: `http://${host}:${port}`,
    }),
    applyDatabaseSchema: async () => ({
      databasePath: "/tmp/operator.db",
      schemaApplied: true,
      status: "applied",
    }),
    openBrowser: async () => undefined,
    writeStdout: (message) => {
      events.push(`stdout:${message}`)
    },
    writeStderr: (message) => {
      events.push(`stderr:${message}`)
    },
    ...overrides,
  }
}
