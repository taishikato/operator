import { spawn } from "node:child_process"
import { once } from "node:events"
import { createServer } from "node:net"

import { resolveAppDataPaths, type AppDataPaths } from "../app-data/app-data.ts"
import {
  applyLocalDatabaseSchema,
  bootstrapLocalDatabase,
} from "../db/local-database.ts"
import type {
  ApplyLocalDatabaseSchemaResult,
  BootstrapLocalDatabaseResult,
} from "../db/local-database.ts"
import { ensureStaleRunsReconciled } from "../runs/run-orchestration.ts"
import { ensureProjectSchedulerRuntimeStarted } from "../scheduler/project-scheduler-runtime.ts"

export type OperatorCliResult = {
  exitCode: number
}

export type StartServerInput = {
  host: string
  port: number
}

export type StartServerResult = {
  url: string
  stop?: () => void | Promise<void>
}

export type RunProcessInput = {
  command: string
  args: string[]
  cwd?: string
}

export type RunProcess = (input: RunProcessInput) => void | Promise<unknown>
export type EnsurePortAvailable = (input: StartServerInput) => Promise<void>

export type OperatorCliDependencies = {
  bootstrapDatabase: () => Promise<BootstrapLocalDatabaseResult>
  applyDatabaseSchema: () => Promise<ApplyLocalDatabaseSchemaResult>
  reconcileStaleRuns: (
    databasePath: string
  ) => Promise<{ interruptedRuns: number }>
  startScheduler: (input: { databasePath: string }) => unknown
  startServer: (input: StartServerInput) => Promise<StartServerResult>
  openBrowser: (url: string) => void | Promise<void>
  writeStdout: (message: string) => void
  writeStderr: (message: string) => void
}

const DEFAULT_HOST = "127.0.0.1"
const DEFAULT_PORT = 3927

export async function runOperatorCli(
  argv: string[],
  dependencies: OperatorCliDependencies
): Promise<OperatorCliResult> {
  const [command, subcommand] = argv
  const shouldOpen = argv.includes("--open")

  if (command === "db" && subcommand === "apply") {
    const result = await dependencies.applyDatabaseSchema()
    dependencies.writeStdout(
      `Operator database schema applied at ${result.databasePath}\n`
    )
    return { exitCode: 0 }
  }

  if (command !== "start") {
    dependencies.writeStderr(
      "Usage: operator start [--open] | operator db apply\n"
    )
    return { exitCode: 1 }
  }

  const database = await dependencies.bootstrapDatabase()
  await dependencies.reconcileStaleRuns(database.databasePath)
  dependencies.startScheduler({ databasePath: database.databasePath })

  let server: StartServerResult
  try {
    server = await dependencies.startServer({
      host: DEFAULT_HOST,
      port: DEFAULT_PORT,
    })
  } catch (error) {
    if (isPortInUseError(error)) {
      dependencies.writeStderr(
        `Port ${DEFAULT_PORT} is already in use on ${DEFAULT_HOST}. Stop the other process and run operator start again.\n`
      )
      return { exitCode: 1 }
    }

    throw error
  }
  dependencies.writeStdout(`Operator is running at ${server.url}\n`)
  if (shouldOpen) {
    await dependencies.openBrowser(server.url)
  }

  return { exitCode: 0 }
}

function isPortInUseError(error: unknown) {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "EADDRINUSE"
  )
}

export async function startNextProductionServer({
  host,
  port,
  runProcess,
  ensurePortAvailable = checkPortAvailable,
}: StartServerInput & {
  runProcess: RunProcess
  ensurePortAvailable?: EnsurePortAvailable
}): Promise<StartServerResult> {
  await ensurePortAvailable({ host, port })
  await runProcess({
    command: "pnpm",
    args: ["exec", "next", "start", "-H", host, "-p", String(port)],
  })

  return {
    url: `http://${host}:${port}`,
  }
}

export function createDefaultOperatorCliDependencies({
  paths = resolveAppDataPaths({}),
  runProcess = spawnOwnedProcess,
}: {
  paths?: AppDataPaths
  runProcess?: RunProcess
} = {}): OperatorCliDependencies {
  return {
    bootstrapDatabase: () => bootstrapLocalDatabase(paths),
    applyDatabaseSchema: () => applyLocalDatabaseSchema(paths),
    reconcileStaleRuns: ensureStaleRunsReconciled,
    startScheduler: ({ databasePath }) =>
      ensureProjectSchedulerRuntimeStarted({ databasePath }),
    startServer: (input) => startNextProductionServer({ ...input, runProcess }),
    openBrowser,
    writeStdout: (message) => process.stdout.write(message),
    writeStderr: (message) => process.stderr.write(message),
  }
}

export async function runOperatorCliMain(argv = process.argv.slice(2)) {
  const dependencies = createDefaultOperatorCliDependencies()

  try {
    const result = await runOperatorCli(argv, dependencies)
    return result.exitCode
  } catch (error) {
    dependencies.writeStderr(`${errorMessage(error)}\n`)
    return 1
  }
}

function spawnOwnedProcess({ command, args, cwd }: RunProcessInput) {
  const child = spawn(command, args, {
    cwd,
    env: process.env,
    stdio: "inherit",
  })

  child.on("exit", (code) => {
    if (typeof code === "number" && code !== 0) {
      process.exitCode = code
    }
  })
}

async function openBrowser(url: string) {
  const { command, args } = browserOpenCommand(url)
  const child = spawn(command, args, {
    detached: true,
    stdio: "ignore",
  })
  child.unref()
  await once(child, "spawn")
}

function browserOpenCommand(url: string) {
  if (process.platform === "darwin") {
    return { command: "open", args: [url] }
  }

  if (process.platform === "win32") {
    return { command: "cmd", args: ["/c", "start", "", url] }
  }

  return { command: "xdg-open", args: [url] }
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error)
}

async function checkPortAvailable({ host, port }: StartServerInput) {
  const server = createServer()

  try {
    await new Promise<void>((resolve, reject) => {
      server.once("error", reject)
      server.listen(port, host, resolve)
    })
  } finally {
    if (server.listening) {
      await new Promise<void>((resolve, reject) => {
        server.close((error) => {
          if (error) {
            reject(error)
            return
          }
          resolve()
        })
      })
    }
  }
}
