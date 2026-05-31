import { mkdir } from "node:fs/promises"
import { isAbsolute, join, relative, resolve } from "node:path"

export type AppDataPaths = {
  appDataDir: string
  databasePath: string
  runLogsDir: string
}

export type ResolveAppDataPathsOptions = {
  appDataRoot?: string
  env?: Partial<NodeJS.ProcessEnv>
  platform?: NodeJS.Platform
}

export function resolveAppDataPaths({
  appDataRoot,
  env = process.env,
  platform = process.platform,
}: ResolveAppDataPathsOptions): AppDataPaths {
  const appDataDir = appDataRoot ?? resolveDefaultAppDataDir(platform, env)

  return {
    appDataDir,
    databasePath: join(appDataDir, "operator.db"),
    runLogsDir: join(appDataDir, "runs"),
  }
}

export async function ensureAppData(paths: AppDataPaths) {
  await mkdir(paths.appDataDir, { recursive: true })
  await mkdir(paths.runLogsDir, { recursive: true })
}

export function createRunLogKey(runId: string) {
  return `runs/${runId}.jsonl`
}

export function resolveRunLogPath(paths: AppDataPaths, logKey: string) {
  if (isAbsolute(logKey)) {
    throw new Error("Run log key must be relative to Operator app data")
  }

  const logPath = resolve(paths.appDataDir, logKey)
  const relativeToRuns = relative(paths.runLogsDir, logPath)

  if (relativeToRuns.startsWith("..") || isAbsolute(relativeToRuns)) {
    throw new Error(
      "Run log key must stay inside the Operator run-log directory"
    )
  }

  return logPath
}

function resolveDefaultAppDataDir(
  platform: NodeJS.Platform,
  env: Partial<NodeJS.ProcessEnv>
) {
  if (platform === "darwin") {
    return join(requireHome(env), "Library", "Application Support", "Operator")
  }

  if (platform === "win32") {
    return join(
      env.APPDATA ?? join(requireHome(env), "AppData", "Roaming"),
      "Operator"
    )
  }

  return join(
    env.XDG_DATA_HOME ?? join(requireHome(env), ".local", "share"),
    "operator"
  )
}

function requireHome(env: Partial<NodeJS.ProcessEnv>) {
  if (!env.HOME) {
    throw new Error("HOME is required to resolve Operator app data directory")
  }

  return env.HOME
}
