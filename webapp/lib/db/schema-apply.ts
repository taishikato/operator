import { spawnSync } from "node:child_process"
import { mkdtemp, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { pathToFileURL } from "node:url"

import type { SchemaApplyOptions } from "./local-database.ts"

export function isAtlasAvailable() {
  const result = spawnSync("atlas", ["version"], { encoding: "utf8" })
  return result.status === 0
}

export async function applyOperatorSchemaWithAtlas({
  databasePath,
  schemaSql,
}: SchemaApplyOptions) {
  const directory = await mkdtemp(join(tmpdir(), "operator-schema-apply-"))
  const schemaSqlPath = join(directory, "schema.sql")

  try {
    await writeFile(schemaSqlPath, schemaSql, "utf8")

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
      { encoding: "utf8" }
    )

    if (result.status !== 0) {
      const detail =
        result.stderr.trim() || result.stdout.trim() || "unknown error"
      throw new Error(`atlas schema apply failed: ${detail}`)
    }
  } finally {
    await rm(directory, { recursive: true, force: true })
  }
}

function sqliteDatabaseUrl(absolutePath: string) {
  return `sqlite://${absolutePath}`
}
