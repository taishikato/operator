import { spawn } from "node:child_process"
import { once } from "node:events"
import { createServer } from "node:net"
import { dirname } from "node:path"
import { fileURLToPath } from "node:url"
import { setTimeout } from "node:timers/promises"

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

export type OperatorCliResult = {
  exitCode: number
}

export type StartServerInput = {
  databasePath: string
  host: string
  port: number
}

export type ServerPortInput = {
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
  env?: Record<string, string>
}

export type ProcessExit = {
  exitCode: number | null
  signal: NodeJS.Signals | null
}

export type StartedProcess = {
  exited?: Promise<ProcessExit>
}

export type RunProcess = (
  input: RunProcessInput
) => void | StartedProcess | Promise<void | StartedProcess>
export type EnsurePortAvailable = (input: ServerPortInput) => Promise<void>
export type WaitForServerReady = (input: {
  processExited?: Promise<ProcessExit>
  url: string
}) => Promise<void>

export type OperatorCliDependencies = {
  bootstrapDatabase: () => Promise<BootstrapLocalDatabaseResult>
  applyDatabaseSchema: () => Promise<ApplyLocalDatabaseSchemaResult>
  ensureStartPortAvailable: (input: ServerPortInput) => Promise<void>
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
  const flags = argv.slice(1)
  const shouldOpen = flags.includes("--open")

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

  let server: StartServerResult
  try {
    await dependencies.ensureStartPortAvailable({
      host: DEFAULT_HOST,
      port: DEFAULT_PORT,
    })
  } catch (error) {
    if (isPortInUseError(error)) {
      dependencies.writeStderr(portInUseMessage())
      return { exitCode: 1 }
    }

    throw error
  }

  const database = await dependencies.bootstrapDatabase()
  if (database.status === "requires_explicit_apply") {
    dependencies.writeStderr(
      "Operator database schema is out of date. Run operator db apply before operator start.\n"
    )
    return { exitCode: 1 }
  }

  await dependencies.reconcileStaleRuns(database.databasePath)

  try {
    server = await dependencies.startServer({
      databasePath: database.databasePath,
      host: DEFAULT_HOST,
      port: DEFAULT_PORT,
    })
  } catch (error) {
    if (isPortInUseError(error)) {
      dependencies.writeStderr(portInUseMessage())
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

function portInUseMessage() {
  return `Port ${DEFAULT_PORT} is already in use on ${DEFAULT_HOST}. Stop the other process and run operator start again.\n`
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
  databasePath,
  host,
  port,
  runProcess,
  ensurePortAvailable = checkPortAvailable,
  waitForServerReady = waitForHttpServer,
}: StartServerInput & {
  runProcess: RunProcess
  ensurePortAvailable?: EnsurePortAvailable
  waitForServerReady?: WaitForServerReady
}): Promise<StartServerResult> {
  const url = `http://${host}:${port}`
  await ensurePortAvailable({ host, port })
  const process = await runProcess({
    command: "pnpm",
    args: ["exec", "next", "start", "-H", host, "-p", String(port)],
    cwd: operatorPackageRoot(),
    env: {
      OPERATOR_CLI_MANAGED_START: "1",
      OPERATOR_DATABASE_PATH: databasePath,
    },
  })
  await waitForServerReady({ processExited: process?.exited, url })

  return {
    url,
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
    ensureStartPortAvailable: checkPortAvailable,
    reconcileStaleRuns: ensureStaleRunsReconciled,
    startScheduler: () => undefined,
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

function spawnOwnedProcess({ command, args, cwd, env }: RunProcessInput) {
  const child = spawn(command, args, {
    cwd,
    env: { ...process.env, ...env },
    stdio: "inherit",
  })

  const exited = new Promise<ProcessExit>((resolve, reject) => {
    child.once("error", reject)
    child.once("exit", (exitCode, signal) => {
      if (typeof exitCode === "number" && exitCode !== 0) {
        process.exitCode = exitCode
      }
      resolve({ exitCode, signal })
    })
  })

  return { exited }
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

async function checkPortAvailable({ host, port }: ServerPortInput) {
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

function operatorPackageRoot() {
  return dirname(dirname(dirname(fileURLToPath(import.meta.url))))
}

async function waitForHttpServer({
  processExited,
  url,
}: {
  processExited?: Promise<ProcessExit>
  url: string
}) {
  const timeoutMs = 30_000
  const startedAt = Date.now()
  let processExit: ProcessExit | null = null
  let processError: unknown = null

  processExited?.then(
    (result) => {
      processExit = result
    },
    (error) => {
      processError = error
    }
  )

  while (Date.now() - startedAt < timeoutMs) {
    if (processError) {
      throw processError
    }

    if (processExit) {
      throw new Error(
        `next start exited before Operator was ready: ${formatProcessExit(processExit)}`
      )
    }

    try {
      await fetch(url, { method: "GET" })
      return
    } catch {
      await setTimeout(250)
    }
  }

  throw new Error(`Timed out waiting for Operator to start at ${url}`)
}

function formatProcessExit({ exitCode, signal }: ProcessExit) {
  if (typeof exitCode === "number") {
    return `exit code ${exitCode}`
  }

  return signal ? `signal ${signal}` : "unknown exit"
}
