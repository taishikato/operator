import { test } from "node:test"
import assert from "node:assert/strict"

import {
  startNextProductionServer,
  runOperatorCli,
  type OperatorCliDependencies,
} from "./operator-cli.ts"
import { shouldStartSchedulerFromWebRequest } from "./operator-runtime-env.ts"

test("operator start defaults to 127.0.0.1:3927 and prints the local URL", async () => {
  const events: string[] = []

  const result = await runOperatorCli(
    ["start"],
    makeDependencies(events, {
      reconcileStaleRuns: async () => {
        events.push("reconcile")
        return { interruptedRuns: 0 }
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
    "server:127.0.0.1:3927",
    "stdout:Operator is running at http://127.0.0.1:3927\n",
  ])
})

test("operator start does not start the scheduler in the CLI parent process", async () => {
  const events: string[] = []

  const result = await runOperatorCli(
    ["start"],
    makeDependencies(events, {
      startScheduler: () => {
        events.push("parent-scheduler")
      },
    })
  )

  assert.equal(result.exitCode, 0)
  assert(!events.includes("parent-scheduler"))
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

test("operator start checks the default port before database side effects", async () => {
  const events: string[] = []
  const portError = Object.assign(new Error("listen EADDRINUSE"), {
    code: "EADDRINUSE",
  })

  const result = await runOperatorCli(
    ["start"],
    makeDependencies(events, {
      ensureStartPortAvailable: async ({ host, port }) => {
        events.push(`port:${host}:${port}`)
        throw portError
      },
      bootstrapDatabase: async () => {
        events.push("bootstrap")
        return {
          databasePath: "/tmp/operator.db",
          schemaApplied: true,
          status: "initialized",
        }
      },
      reconcileStaleRuns: async () => {
        events.push("reconcile")
        return { interruptedRuns: 0 }
      },
      startServer: async () => {
        events.push("server")
        return { url: "http://127.0.0.1:3927" }
      },
    })
  )

  assert.equal(result.exitCode, 1)
  assert.deepEqual(events, [
    "port:127.0.0.1:3927",
    "stderr:Port 3927 is already in use on 127.0.0.1. Stop the other process and run operator start again.\n",
  ])
})

test("operator start stops before reconciliation when the database requires explicit apply", async () => {
  const events: string[] = []

  const result = await runOperatorCli(
    ["start"],
    makeDependencies(events, {
      bootstrapDatabase: async () => {
        events.push("bootstrap")
        return {
          databasePath: "/tmp/operator.db",
          schemaApplied: false,
          status: "requires_explicit_apply",
        }
      },
      reconcileStaleRuns: async () => {
        events.push("reconcile")
        return { interruptedRuns: 0 }
      },
      startServer: async () => {
        events.push("server")
        return { url: "http://127.0.0.1:3927" }
      },
    })
  )

  assert.equal(result.exitCode, 1)
  assert.deepEqual(events, [
    "bootstrap",
    "stderr:Operator database schema is out of date. Run operator db apply before operator start.\n",
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
  const spawned: Array<{
    args: string[]
    command: string
    cwd?: string
    env?: Record<string, string>
  }> = []

  const result = await startNextProductionServer({
    host: "127.0.0.1",
    port: 3927,
    databasePath: "/tmp/operator.db",
    ensurePortAvailable: async () => undefined,
    waitForServerReady: async () => undefined,
    runProcess: async ({ command, args, cwd, env }) => {
      spawned.push({ command, args, cwd, env })
    },
  })

  assert.equal(result.url, "http://127.0.0.1:3927")
  assert.deepEqual(spawned, [
    {
      command: "pnpm",
      args: ["exec", "next", "start", "-H", "127.0.0.1", "-p", "3927"],
      env: {
        OPERATOR_CLI_MANAGED_START: "1",
        OPERATOR_DATABASE_PATH: "/tmp/operator.db",
      },
      cwd: process.cwd(),
    },
  ])
})

test("startNextProductionServer waits until next is listening before reporting success", async () => {
  const events: string[] = []

  const result = await startNextProductionServer({
    host: "127.0.0.1",
    port: 3927,
    databasePath: "/tmp/operator.db",
    ensurePortAvailable: async () => {
      events.push("port")
    },
    runProcess: async () => {
      events.push("spawn")
    },
    waitForServerReady: async ({ url }) => {
      events.push(`ready:${url}`)
    },
  })

  assert.equal(result.url, "http://127.0.0.1:3927")
  assert.deepEqual(events, ["port", "spawn", "ready:http://127.0.0.1:3927"])
})

test("startNextProductionServer checks port availability before spawning next", async () => {
  const spawned: string[] = []
  const portError = Object.assign(new Error("busy"), { code: "EADDRINUSE" })

  await assert.rejects(
    startNextProductionServer({
      host: "127.0.0.1",
      port: 3927,
      databasePath: "/tmp/operator.db",
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

test("startNextProductionServer reports child process startup errors", async () => {
  const spawnError = Object.assign(new Error("spawn pnpm ENOENT"), {
    code: "ENOENT",
  })

  await assert.rejects(
    startNextProductionServer({
      host: "127.0.0.1",
      port: 3927,
      databasePath: "/tmp/operator.db",
      ensurePortAvailable: async () => undefined,
      runProcess: async () => ({
        exited: Promise.reject(spawnError),
      }),
    }),
    spawnError
  )
})

test("operator start only accepts --open after the start command", async () => {
  const events: string[] = []

  const result = await runOperatorCli(
    ["--open", "start"],
    makeDependencies(events)
  )

  assert.equal(result.exitCode, 1)
  assert.deepEqual(events, [
    "stderr:Usage: operator start [--open] | operator db apply\n",
  ])
})

test("web requests skip scheduler startup during CLI-managed startup", () => {
  assert.equal(
    shouldStartSchedulerFromWebRequest({ OPERATOR_CLI_MANAGED_START: "1" }),
    false
  )
  assert.equal(shouldStartSchedulerFromWebRequest({}), true)
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
    ensureStartPortAvailable: async () => undefined,
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
