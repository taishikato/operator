export type CursorApiKeyStatus = "configured" | "missing"

export type AppOperationalStatus = {
  appDataDir: string
  cursorApiKeyStatus: CursorApiKeyStatus
  version: string
}

export function getAppOperationalStatus({
  appDataDir,
  env = process.env,
  version,
}: {
  appDataDir: string
  env?: Partial<NodeJS.ProcessEnv>
  version: string
}): AppOperationalStatus {
  return {
    appDataDir,
    cursorApiKeyStatus: hasCursorApiKey(env) ? "configured" : "missing",
    version,
  }
}

function hasCursorApiKey(env: Partial<NodeJS.ProcessEnv>) {
  return typeof env.CURSOR_API_KEY === "string" && env.CURSOR_API_KEY.trim() !== ""
}
