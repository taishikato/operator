import { spawnSync } from "node:child_process"
import { pathToFileURL } from "node:url"

export function isAtlasAvailable() {
  const result = spawnSync("atlas", ["version"], { encoding: "utf8" })
  return result.status === 0
}

export function applySpikeSchemaWithAtlas({
  databasePath,
  schemaSqlPath,
}: {
  databasePath: string
  schemaSqlPath: string
}) {
  const result = spawnSync(
    "atlas",
    [
      "schema",
      "apply",
      "-u",
      sqliteDatabaseUrl(databasePath),
      "--to",
      pathToFileURL(schemaSqlPath).href,
      "--dev-url",
      "sqlite://dev?mode=memory",
      "--auto-approve",
    ],
    { encoding: "utf8" },
  )

  if (result.status !== 0) {
    const detail = result.stderr.trim() || result.stdout.trim() || "unknown error"
    throw new Error(`atlas schema apply failed: ${detail}`)
  }
}

function sqliteDatabaseUrl(absolutePath: string) {
  return `sqlite://${absolutePath}`
}
